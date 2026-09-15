module RaidLog
  # Adds the 4 RAID log list views (public, starred "work_packages_table"
  # Queries, each filtered to one RAID type) to a project's Work packages
  # sidebar, so Risks/Issues/Actions/Decisions show up as a click-through
  # list -- under the "Starred views" section, alongside the default
  # views -- without an admin having to build one by hand per project.
  # Used both to backfill existing projects (migration) and to seed brand
  # new ones (RaidLog::DashboardSeeding, hooked on Project#after_create).
  #
  # A view only renders in the sidebar once it has an associated View
  # record of the matching type (see WorkPackages::Menu#base_query, which
  # joins queries to views on views.type = "work_packages_table") -- a
  # bare starred Query is not enough on its own.
  #
  # Idempotent: skips a view if a query with its exact name already exists
  # for the project.
  #
  # Each entry's `columns` is the exact, ordered column list for that
  # view -- plain strings pass straight to Query#column_names= (base work
  # package attributes: id, subject, status, created_at, author, ...);
  # `{ cf: "Custom Field Name" }` resolves to that type's custom field at
  # save time. "description" is deliberately never in one of these lists
  # -- OpenProject's work package table doesn't support rich-text
  # description as a column at all (Query#displayable_columns excludes
  # it), only the split/full view shows it.
  class ListViewsService
    VIEWS = [
      {
        type_name: "Risk",
        title: "Risks",
        columns: [
          "id", { cf: "Risk Type" }, "created_at", "author", { cf: "Risk Status" }, { cf: "Owner" },
          "subject", { cf: "Mitigation Action" }, { cf: "Probability" }, { cf: "Impact" }, { cf: "Score" },
          { cf: "Latest Update" }, { cf: "Notes" }
        ]
      },
      {
        type_name: "Issue",
        title: "Issues",
        columns: [
          "id", { cf: "Issue Type" }, "created_at", "author", { cf: "Owner" }, { cf: "RAID Status" },
          "subject", { cf: "Issue Impact" }, "priority", { cf: "Root Cause" }, { cf: "Resolution Action" },
          { cf: "Last Updated By" }, { cf: "Date Resolved" }, { cf: "Notes" }
        ]
      },
      {
        type_name: "Action",
        title: "Actions",
        columns: [
          "id", { cf: "Action Category" }, "created_at", "author", { cf: "Owner" }, { cf: "RAID Status" },
          "subject", { cf: "Latest Update" }, { cf: "Last Updated By" }, { cf: "Date Resolved" }, { cf: "Notes" }
        ]
      },
      {
        type_name: "Decision",
        title: "Decisions",
        columns: [
          "id", { cf: "Decision Category" }, "created_at", "author", { cf: "Owner" }, { cf: "Decision Status" },
          "subject", { cf: "Latest Update" }, { cf: "Last Updated By" }, { cf: "Approved Date" }, { cf: "Notes" }
        ]
      }
    ].freeze

    def self.call(project)
      new(project).call
    end

    # Reused by db/migrate/20260909100000_update_raid_log_risks_columns.rb
    # to backfill the column list on Query records this service already
    # created for existing projects (that migration can't just call #call
    # again -- it's a no-op once a "Risks" query already exists).
    def self.resolve_columns(columns)
      columns.filter_map do |column|
        next column if column.is_a?(String)

        field = WorkPackageCustomField.find_by(name: column[:cf])
        "cf_#{field.id}" if field
      end
    end

    def initialize(project)
      @project = project
    end

    def call
      return if VIEWS.all? { |view| Query.exists?(project: @project, name: view[:title]) }

      User.execute_as(User.system) do
        VIEWS.each do |view|
          next if Query.exists?(project: @project, name: view[:title])

          build_view(view)
        end
      end
    end

    private

    def build_view(view)
      type = Type.find_by(name: view[:type_name])
      return unless type

      query = Query.new(project: @project, user: User.system, name: view[:title], public: true, starred: true)
      query.include_subprojects = false
      query.add_filter("type_id", "=", [type.id.to_s])
      query.column_names = self.class.resolve_columns(view[:columns])
      query.sort_criteria = [["id", "desc"]]
      return unless query.save

      View.create!(query:, type: "work_packages_table")
    end
  end
end
