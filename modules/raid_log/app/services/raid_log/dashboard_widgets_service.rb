module RaidLog
  # Adds the 4 RAID log status-distribution charts (native "Work packages
  # graph" widgets, each backed by a public Query grouped by the relevant
  # status custom field and filtered to one RAID type) to a project's
  # dashboard grid. Used both to backfill existing projects (migration) and
  # to seed brand new ones (RaidLog::DashboardSeeding, hooked on
  # Project#after_create).
  #
  # Idempotent: skips a chart if a query with its exact name already exists
  # for the project.
  class DashboardWidgetsService
    CHARTS = [
      { type_name: "Risk", status_field: "Risk Status", title: "Risk Distribution by Status" },
      { type_name: "Issue", status_field: "RAID Status", title: "Issue Distribution by Status" },
      { type_name: "Action", status_field: "RAID Status", title: "Action Items by Status" },
      { type_name: "Decision", status_field: "Decision Status", title: "Decisions by Status" }
    ].freeze

    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      return if CHARTS.all? { |chart| Query.exists?(project: @project, name: chart[:title]) }

      User.execute_as(User.system) do
        grid = find_or_build_grid
        next_row = (grid.widgets.map(&:end_row).max || 1)

        CHARTS.each_slice(2).with_index do |pair, row_index|
          row = next_row + row_index
          pair.each_with_index do |chart, col_index|
            next if Query.exists?(project: @project, name: chart[:title])

            query = build_query(chart)
            next unless query.persisted?

            grid.widgets.build(
              identifier: "work_packages_graph",
              start_row: row,
              end_row: row + 1,
              start_column: col_index + 1,
              end_column: col_index + 2,
              options: { "name" => chart[:title], "queryId" => query.id.to_s, "chartType" => "bar" }
            )
          end
        end

        grid.row_count = [grid.row_count.to_i, next_row + (CHARTS.size / 2.0).ceil].max
        grid.save!
      end
    end

    private

    def find_or_build_grid
      grid = Grids::Overview.find_by(project: @project)
      return grid if grid

      defaults = Overviews::GridRegistration.defaults
      grid = Grids::Overview.new(project: @project, row_count: defaults[:row_count], column_count: defaults[:column_count])
      defaults[:widgets].each { |widget| grid.widgets << widget }
      grid
    end

    def build_query(chart)
      type = Type.find_by(name: chart[:type_name])
      status_field = WorkPackageCustomField.find_by(name: chart[:status_field])
      return Query.new unless type && status_field

      query = Query.new(project: @project, user: User.system, name: chart[:title], public: true)
      query.include_subprojects = false
      query.add_filter("type_id", "=", [type.id.to_s])
      query.group_by = "cf_#{status_field.id}"
      query.column_names = ["id"]
      query.save
      query
    end
  end
end
