module PmoDashboard
  # Computes everything the redesigned PMO Dashboard card needs for one
  # project: schedule range, per-phase expected/actual progress, risk/issue
  # severity + resolution mix, and invoicing status.
  #
  # "Delivery" work packages exclude the auxiliary types this fork added
  # (Payment, Contract Line, Risk, Issue, Action, Decision) -- those don't
  # carry meaningful hour estimates/progress and would just dilute the
  # numbers. Risk/Issue are used separately, only for the severity chart.
  class ProjectSummary
    EXCLUDED_TYPE_NAMES = ["Payment", "Contract Line", "Risk", "Issue", "Action", "Decision"].freeze
    SEVERITY_LEVELS = ["Critical", "High", "Medium", "Low"].freeze
    IN_PROGRESS_STATUS_NAME = "In progress".freeze
    RESOLVED_RISK_STATUSES = ["Closed"].freeze
    RESOLVED_ISSUE_STATUSES = ["Resolved", "Closed"].freeze

    def initialize(project)
      @project = project
    end

    def call
      phases = phase_summaries

      {
        project: @project,
        client: client_name,
        start_date:,
        end_date:,
        progress_percent:,
        total_count:,
        in_progress_count:,
        planned_hours: planned_hours.round(1),
        actual_hours: actual_hours.round(1),
        phases:,
        expected_completion_percent: date_based_percent(start_date, end_date),
        actual_completion_percent: average_percent(phases.map { |p| p[:actual_completion] }),
        severity: severity_counts,
        resolved_count:,
        open_count:,
        invoices: invoice_summary
      }
    end

    private

    def client_name
      field = ProjectCustomField.find_by(name: "Client")
      return nil unless field

      @project.custom_value_for(field)&.formatted_value
    end

    def delivery_work_packages
      @delivery_work_packages ||= @project.work_packages.where.not(type: excluded_types)
    end

    def excluded_types
      Type.where(name: EXCLUDED_TYPE_NAMES)
    end

    def start_date
      delivery_work_packages.minimum(:start_date)
    end

    def end_date
      delivery_work_packages.maximum(:due_date)
    end

    def total_count
      delivery_work_packages.count
    end

    def in_progress_count
      delivery_work_packages.joins(:status).where(statuses: { name: IN_PROGRESS_STATUS_NAME }).count
    end

    def progress_percent
      ratios = delivery_work_packages.where.not(done_ratio: nil).pluck(:done_ratio)
      return 0 if ratios.empty?

      (ratios.sum.to_f / ratios.size).round
    end

    # Per the user: Actual Hours = Planned Hours weighted by each work
    # package's own Expected Completion % (schedule-based "if on schedule,
    # how far should this be by now"), used as a stand-in for actually-
    # logged effort. Computed per work package, not one project-wide %.
    def planned_hours
      delivery_work_packages.sum(:estimated_hours) || 0
    end

    def actual_hours
      delivery_work_packages.where.not(estimated_hours: nil).sum do |wp|
        wp.estimated_hours.to_f * (wp.expected_completion || 0) / 100.0
      end
    end

    # "Milestones" on the card are this project's own Summary Task work
    # packages -- not the separate Project::Phase life-cycle concept used
    # before. Per the user: Expected/Actual should reflect each summary
    # task's own rolled-up progress across however many children it has
    # (the same "parent aggregates its children automatically" behavior
    # MS Project shows), rather than a hand-maintained phase-to-work-
    # package tagging step.
    #
    # Includes both the top level AND the second level (a summary task's
    # own summary-task children), flattened into one list rather than
    # nested -- each level-1 item immediately followed by its own level-2
    # children, so the list still reads as grouped without needing a tree
    # UI. Anything deeper than level 2 is not included.
    #
    # derived_done_ratio (a real, stored column OpenProject already
    # maintains for every parent work package under "Weighted by work"
    # hierarchy totals) is the correct native rollup -- NOT done_ratio,
    # which is the work package's own unweighted value and ignores
    # children entirely. expected_completion (WorkPackages::
    # ExpectedCompletion) already uses derived_start_date/derived_due_date
    # for parents, so it naturally spans the full subtree too.
    def phase_summaries
      top_level = @project.work_packages
                           .where(parent_id: nil)
                           .joins(:type)
                           .where(types: { name: "Summary task" })
                           .order(:id)
                           .to_a

      milestones = top_level.flat_map do |wp|
        [wp, *wp.children.joins(:type).where(types: { name: "Summary task" }).order(:id)]
      end

      milestones.map { |wp| milestone_summary(wp) }
    end

    def milestone_summary(wp)
      {
        id: wp.id,
        name: wp.subject,
        start_date: wp.derived_start_date || wp.start_date,
        end_date: wp.derived_due_date || wp.due_date,
        expected_completion: wp.expected_completion || 0,
        actual_completion: wp.derived_done_ratio || wp.done_ratio || 0
      }
    end

    def average_percent(values)
      values = values.compact
      return 0 if values.empty?

      (values.sum.to_f / values.size).round
    end

    def date_based_percent(start, finish)
      return nil if start.nil? || finish.nil?

      today = Date.current
      return 0 if today < start
      return 100 if today >= finish || finish == start

      ((today - start).to_f / (finish - start).to_f * 100).round
    end

    def severity_counts
      counts = SEVERITY_LEVELS.index_with { 0 }

      tally_severity!(counts, "Risk", "Impact")
      tally_severity!(counts, "Issue", "Issue Impact")

      counts
    end

    def tally_severity!(counts, type_name, field_name)
      type = Type.find_by(name: type_name)
      field = WorkPackageCustomField.find_by(name: field_name)
      return unless type && field

      @project.work_packages.where(type:).find_each do |wp|
        value = wp.typed_custom_value_for(field)
        counts[value] += 1 if counts.key?(value)
      end
    end

    def resolved_count
      risk_type = Type.find_by(name: "Risk")
      issue_type = Type.find_by(name: "Issue")
      risk_status_field = WorkPackageCustomField.find_by(name: "Risk Status")
      raid_status_field = WorkPackageCustomField.find_by(name: "RAID Status")

      resolved = 0
      if risk_type && risk_status_field
        resolved += count_with_status(risk_type, risk_status_field, RESOLVED_RISK_STATUSES)
      end
      if issue_type && raid_status_field
        resolved += count_with_status(issue_type, raid_status_field, RESOLVED_ISSUE_STATUSES)
      end
      resolved
    end

    def count_with_status(type, field, resolved_values)
      @project.work_packages.where(type:).count do |wp|
        resolved_values.include?(wp.typed_custom_value_for(field))
      end
    end

    def open_count
      [severity_counts.values.sum - resolved_count, 0].max
    end

    # Per the user: this is a 3-stage pipeline over every payment line
    # (not just the ones someone remembered to flag), not two independent
    # yes/no filters --
    #   Remaining  = not invoiced yet at all
    #   Issued     = invoiced, but not yet collected (outstanding AR)
    #   Collected  = actually paid
    # so a line moves Remaining -> Issued -> Collected as its own
    # `invoiced`/`collected` flags get checked, and the three counts
    # always add up to the total number of payment lines on the project.
    def invoice_summary
      payments = PaymentTerms::Payment
                 .joins(contract_line: :project)
                 .where(payment_terms_contract_lines: { project_id: @project.id })

      total_count = payments.count
      total_amount = payments.sum(:value) || 0

      collected = payments.where(collected: true)
      issued = payments.where(invoiced: true, collected: false)

      collected_count = collected.count
      collected_amount = collected.sum(:value) || 0
      issued_count = issued.count
      issued_amount = issued.sum(:value) || 0

      invoiced_total_count = issued_count + collected_count

      {
        issued_count:,
        collected_count:,
        remaining_count: total_count - invoiced_total_count,
        issued_amount:,
        collected_amount:,
        remaining_amount: total_amount - issued_amount - collected_amount,
        collection_rate: invoiced_total_count.positive? ? ((collected_count.to_f / invoiced_total_count) * 100).round : 0
      }
    end
  end
end
