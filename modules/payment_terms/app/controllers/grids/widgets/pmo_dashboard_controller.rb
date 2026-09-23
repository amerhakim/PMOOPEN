class Grids::Widgets::PmoDashboardController < Grids::WidgetController
  # Same permission as the rest of payment_terms -- see
  # modules/payment_terms/lib/payment_terms/engine.rb. Sets @project and
  # 403s if the current user lacks view_payment_terms in it, on top of the
  # base class's generic project-visibility check.
  load_and_authorize_with_permission_in_project :view_payment_terms, only: [:show]

  def show
    render_widget Grids::Widgets::PmoDashboard.new(@project)
  end
end
