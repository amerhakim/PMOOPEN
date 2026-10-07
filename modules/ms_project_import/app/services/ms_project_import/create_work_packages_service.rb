module MsProjectImport
  # Maps MPXJ's parsed task list onto OpenProject WorkPackages, preserving the
  # source file's WBS hierarchy, dates and predecessor/successor dependencies
  # (including FS/SS/FF/SF scheduling relation types and lag).
  class CreateWorkPackagesService
    # MPXJ serializes durations/lags in seconds; OpenProject relation lag is
    # in working days, assuming an 8-hour working day.
    SECONDS_PER_WORKDAY = 8 * 3600

    TYPE_NAME_FOR_MILESTONE = "Milestone".freeze
    TYPE_NAME_FOR_SUMMARY = "Summary task".freeze
    TYPE_NAME_DEFAULT = "Task".freeze

    def initialize(project:, user:, parsed:)
      @project = project
      @user = user
      @tasks = Array(parsed[:tasks])
    end

    # The types every PMO project works with (same set the RAID Log and the
    # hand-made projects use). Projects created in bulk (imports) can have no
    # work package types enabled at all, and then no task can be created.
    DEFAULT_TYPE_NAMES = ["Task", "Milestone", "Summary task", "Risk", "Issue", "Action", "Decision"].freeze

    def call
      id_map = {}
      original_schedule = {}
      tasks_created = 0
      @first_error = nil

      ensure_project_types

      tasks.each do |task|
        wp = build_work_package(task, id_map)

        if wp&.persisted?
          id_map[task[:unique_id]] = wp
          original_schedule[wp.id] = captured_schedule(wp)
          tasks_created += 1
        end
      end

      if tasks_created.zero? && tasks.any?
        raise "No task could be created in this project#{": #{@first_error}" if @first_error}"
      end

      relations_created = create_relations(id_map)
      restore_original_schedule(original_schedule)

      { tasks_created:, relations_created: }
    end

    private

    attr_reader :project, :user, :tasks

    # The import itself is gated by the `import_ms_project` permission (checked
    # in the controller against the uploading `user`). The actual work package
    # and relation creation runs as the system user so the import isn't also
    # limited by *unrelated* permissions (add_work_packages,
    # manage_work_package_relations) that some PMO roles don't hold by design
    # (e.g. PMO Director is intentionally a non-hands-on governance role).
    def acting_user
      @acting_user ||= User.system
    end

    def ensure_project_types
      return if project.types.exists?

      project.types = Type.where(name: DEFAULT_TYPE_NAMES).to_a
    end

    def build_work_package(task, id_map)
      attributes = {
        project:,
        type: type_for(task),
        subject: task[:name].presence || "Untitled task",
        start_date: parse_date(task[:start]),
        due_date: parse_date(task[:finish] || task[:start]),
        schedule_manually: true,
        # Without this, OpenProject silently snaps a start/due date that
        # falls on what ITS OWN project calendar considers a non-working
        # day forward to the next working day -- even in manual scheduling
        # mode. The source file's own dates are what this import is
        # supposed to reproduce exactly, regardless of which days this
        # project's calendar happens to mark as working ones.
        ignore_non_working_days: true
      }

      parent = id_map[task[:parent_task_unique_id]]
      attributes[:parent] = parent if parent
      attributes[:done_ratio] = task[:percent_complete].round if settable_done_ratio?(task)

      call = WorkPackages::CreateService
             .new(user: acting_user)
             .call(**attributes, send_notifications: false)

      unless call.success?
        @first_error ||= call.errors.full_messages.to_sentence
        Rails.logger.warn(
          "MsProjectImport: skipped task #{task[:unique_id]} (#{task[:name]}): #{call.errors.full_messages.join(', ')}"
        )
      end

      call.result
    end

    def settable_done_ratio?(task)
      Setting.work_package_done_ratio == "field" && task[:percent_complete].present?
    end

    def type_for(task)
      name =
        if task[:milestone]
          TYPE_NAME_FOR_MILESTONE
        elsif task[:summary]
          TYPE_NAME_FOR_SUMMARY
        else
          TYPE_NAME_DEFAULT
        end

      project.types.find_by(name:) ||
        project.types.first ||
        Type.find_by(name: TYPE_NAME_DEFAULT) ||
        Type.first
    end

    def parse_date(value)
      return nil if value.blank?

      Time.zone.parse(value).to_date
    rescue ArgumentError, TypeError
      nil
    end

    def captured_schedule(wp)
      {
        start_date: wp.start_date,
        due_date: wp.due_date,
        duration: wp.duration,
        schedule_manually: wp.schedule_manually,
        ignore_non_working_days: wp.ignore_non_working_days
      }
    end

    # Creating a "follows" relation has a real, documented side effect in
    # core OpenProject (Relations::Concerns::Rescheduling): the FIRST
    # predecessor relation on a leaf work package silently switches it
    # from manual to automatic scheduling and recalculates its dates from
    # the predecessor using THIS project's own working-day calendar --
    # which is almost never the same calendar the source MS Project file
    # used, so the recalculated dates/duration routinely don't match the
    # file at all. That's fine for someone wiring up a relation by hand in
    # the UI (the whole point is to let OpenProject reschedule), but wrong
    # for an import that's supposed to reproduce the file exactly. Putting
    # every imported task's schedule back to what it was right after its
    # own creation -- before any relation could touch it -- undoes that
    # side effect without needing to touch the core relation/scheduling
    # code at all.
    def restore_original_schedule(original_schedule)
      return if original_schedule.empty?

      WorkPackage.where(id: original_schedule.keys).find_each do |wp|
        original = original_schedule[wp.id]
        next if captured_schedule(wp) == original

        wp.update_columns(original)
      end
    end

    def create_relations(id_map)
      created = 0

      tasks.each do |task|
        Array(task[:predecessors]).each do |predecessor_entry|
          predecessor_wp = id_map[predecessor_entry[:predecessor_task_unique_id]]
          successor_wp = id_map[predecessor_entry[:successor_task_unique_id]]

          next unless predecessor_wp && successor_wp
          next if predecessor_wp == successor_wp

          call = Relations::CreateService.new(user: acting_user).call(
            from: successor_wp,
            to: predecessor_wp,
            relation_type: Relation::TYPE_FOLLOWS,
            schedule_relation_type: normalize_schedule_type(predecessor_entry[:type]),
            lag: lag_in_days(predecessor_entry[:lag]),
            send_notifications: false
          )

          if call.success?
            created += 1
          else
            Rails.logger.warn(
              "MsProjectImport: skipped relation #{predecessor_entry[:predecessor_task_unique_id]} -> " \
              "#{predecessor_entry[:successor_task_unique_id]}: #{call.errors.full_messages.join(', ')}"
            )
          end
        end
      end

      created
    end

    def normalize_schedule_type(type)
      return Relation::SCHEDULE_RELATION_TYPE_FS unless Relation::SCHEDULE_RELATION_TYPES.include?(type)

      type
    end

    def lag_in_days(seconds)
      return 0 if seconds.blank? || seconds.to_f.zero?

      (seconds.to_f / SECONDS_PER_WORKDAY).round
    end
  end
end
