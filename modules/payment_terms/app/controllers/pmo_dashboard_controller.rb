class PmoDashboardController < ApplicationController
  # Without this, `my_projects` (no @project, so the project-menu fallback
  # in Redmine::MenuManager::MenuHelper#render_main_menu never kicks in)
  # renders with no menu_name at all -- base.html.erb then treats it like
  # a bare global page (its own comment: "For some global pages such as
  # home") and drops the sidebar entirely. "global" is the same layout
  # HomescreenController and Costs::My::TimeTrackingController use for
  # the identical situation.
  #
  # Deliberately NOT `layout "global", only: :my_projects` -- that looks
  # like it should fall back to ApplicationController's `layout "base"`
  # for every other action, but it doesn't: Rails' only:/except: layout
  # conditions don't inherit from the superclass when they don't match,
  # they render with NO layout at all (confirmed live: `show` came back
  # as a bare fragment, empty <head>, none of the app chrome, not just a
  # missing sidebar). Naming both cases explicitly avoids relying on
  # that fallback.
  layout :pmo_dashboard_layout

  before_action :find_project, only: [:show]
  before_action :authorize, only: [:show]
  before_action :require_login, only: [:my_projects]

  # my_projects spans every project the user has access to -- no single
  # @project to run the declarative `authorize` check against, see
  # PaymentTermsController#my_projects for the same pattern.
  no_authorization_required! :my_projects

  menu_item :pmo_dashboard

  def show
    @summary = PmoDashboard::ProjectSummary.new(@project).call
  end

  def my_projects
    projects = Project.allowed_to(current_user, :view_payment_terms).order(:name)
    @summaries = projects.map { |project| PmoDashboard::ProjectSummary.new(project).call }
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def pmo_dashboard_layout
    action_name == "my_projects" ? "global" : "base"
  end
end
