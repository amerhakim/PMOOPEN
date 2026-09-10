module Grids
  module Widgets
    # Rails-rendered content for the "PMO Dashboard" grid widget (see
    # frontend/module/pmo-dashboard-widget for the Angular side that embeds
    # this via a turbo-frame). Reuses the exact same card partial as the
    # standalone /projects/:id/pmo_dashboard page -- one KPI card, computed
    # by PmoDashboard::ProjectSummary.
    class PmoDashboard < Grids::WidgetComponent
      param :project

      def title
        I18n.t(:label_pmo_dashboard)
      end

      def summary
        @summary ||= ::PmoDashboard::ProjectSummary.new(project).call
      end
    end
  end
end
