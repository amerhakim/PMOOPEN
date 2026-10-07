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
  before_action :require_login, only: %i[my_projects cards]

  # my_projects spans every project the user has access to -- no single
  # @project to run the declarative `authorize` check against, see
  # PaymentTermsController#my_projects for the same pattern.
  no_authorization_required! :my_projects, :cards

  menu_item :pmo_dashboard

  def show
    @summary = PmoDashboard::ProjectSummary.new(@project).call
  end

  # Tab-scoped the same way as PaymentTermsController#analytics: a PMO
  # Director (or admin) sees an "All Projects" tab plus one tab per real
  # Project Manager found across every visible project; anyone else sees a
  # single tab scoped to the projects where THEY hold the Project Manager
  # role. Within each tab/scope, projects (and thus their cards) are sorted
  # active-first, closed-last -- the cards themselves are untouched, only
  # the order they're handed to the view changes.
  def my_projects
    is_director = pmo_director_or_admin?
    projects = visible_pmo_projects(is_director)
    pm_by_project = project_manager_members_by_project(projects)

    @scopes =
      if is_director
        pm_users = pm_by_project.values.flatten(1).uniq.sort_by { |_, name| name }
        [{ key: "all", label: t("pmo_dashboard.all_projects_tab"), projects: projects }] +
          pm_users.map do |user_id, name|
            ids = pm_by_project.select { |_, members| members.any? { |uid, _| uid == user_id } }.keys
            { key: "pm-#{user_id}", label: name, projects: projects.select { |p| ids.include?(p.id) } }
          end
      else
        ids = pm_by_project.select { |_, members| members.any? { |uid, _| uid == User.current.id } }.keys
        [{ key: "mine", label: t("pmo_dashboard.my_projects_tab"), projects: projects.select { |p| ids.include?(p.id) } }]
      end

    # The page itself only needs cheap project-level data: the overview
    # numbers and the (ordered) list of live projects. A card's heavy
    # summary is computed on demand, three at a time, by #cards as the
    # carousel pages through -- so load time doesn't grow with the number
    # of projects. Archived projects never get a card, only a count.
    # Running projects come first, finished-but-not-yet-collected last.
    @scopes.each do |scope|
      live, archived = scope[:projects].partition(&:active?)
      scope[:live] = live.sort_by { |p| [helpers.pmo_health_key(p) == "finished" ? 1 : 0, p.name] }
      scope[:overview] = build_scope_overview(scope[:live], archived)
    end
    @has_any_scope_data = @scopes.any? { |s| s[:projects].any? }
  end

  # HTML for the requested projects' cards, as { "<project id>": "<html>" }.
  # Only projects the current user can actually see on the dashboard are
  # rendered; anything else is silently left out.
  def cards
    ids = params[:ids].to_s.split(",").map(&:to_i).first(12)
    visible = visible_pmo_projects(pmo_director_or_admin?).select { |p| p.active? && ids.include?(p.id) }

    html = visible.to_h do |project|
      [project.id.to_s, render_to_string(partial: "pmo_dashboard/card", formats: [:html], locals: { summary: summary_for(project) })]
    end
    render json: html
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def pmo_dashboard_layout
    %w[my_projects].include?(action_name) ? "global" : "base"
  end

  # Same rule as PaymentTermsController#pmo_director_or_admin? -- a PMO
  # Director (or admin) sees every project regardless of membership.
  def pmo_director_or_admin?
    User.current.admin? || User.current.memberships.any? { |m| m.roles.exists?(name: "PMO Director") }
  end

  # Same rule as PaymentTermsController#visible_projects_for_my_projects --
  # a director isn't limited to projects they personally belong to, everyone
  # else only sees what their own view_payment_terms permission grants.
  # Archived projects drop out of Project.allowed_to, so a non-director
  # gets theirs back through their Project/Program Manager membership.
  def visible_pmo_projects(is_director)
    if is_director
      Project.where(id: PaymentTerms::ContractLine.select(:project_id).distinct).to_a
    else
      managed = Member.joins(:roles)
                      .where(user_id: User.current.id, roles: { name: PaymentTerms::CreateInvoiceOverdueNotificationsJob::MANAGER_ROLE_NAMES })
                      .select(:project_id)
      archived = Project.where(active: false, id: managed).where(id: PaymentTerms::ContractLine.select(:project_id)).to_a
      Project.allowed_to(current_user, :view_payment_terms).to_a + archived
    end
  end

  # One project's card data, computed once per request (the same project
  # appears in several tabs) and cached for a few minutes across requests.
  def summary_for(project)
    @summary_memo ||= {}
    @summary_memo[project.id] ||= begin
      data = Rails.cache.fetch(["pmo-summary-v1", project.id, project.updated_at.to_i], expires_in: 5.minutes) do
        PmoDashboard::ProjectSummary.new(project).call.except(:project)
      end
      data.merge(project:)
    end
  end

  # Same lookup as PaymentTermsController#project_manager_members_by_project,
  # keyed by user id (not just name) so a same-named user can't be confused
  # with another, and so the current user can be matched reliably.
  def project_manager_members_by_project(projects)
    return {} if projects.empty?

    Member.joins(:roles)
          .where(project_id: projects.map(&:id), roles: { name: "Project Manager" })
          .includes(:principal)
          .distinct
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |member, hash|
      hash[member.project_id] << [member.user_id, member.principal.name]
    end
  end

  # One tab's overview numbers: KPI counts, native project status mix
  # (OpenProject's own on track / at risk / off track / finished), and the
  # projects-per-department breakdown read from a "Department" project
  # custom field (empty when that field hasn't been created yet).
  def build_scope_overview(projects, archived_projects = [])
    everything = projects + archived_projects
    by_health = projects.group_by { |p| helpers.pmo_health_key(p) }
    count = ->(key) { by_health.fetch(key, []).size }

    on_track = count.call("on_track")
    at_risk = count.call("at_risk")
    off_track = count.call("off_track")
    rated = on_track + at_risk + off_track
    month_start = Time.current.beginning_of_month

    finished = count.call("finished")

    {
      total: everything.size,
      prior_total: everything.count { |p| p.created_at < month_start },
      # Running = live and not finished; Completed = finished but not yet
      # archived (money still to collect); Archived = closed. The three are
      # mutually exclusive so they always add up to the total.
      active: projects.size - finished,
      archived: archived_projects.size,
      on_track:, at_risk:, off_track:,
      finished:,
      none: count.call("none"),
      health_percent: rated.positive? ? (on_track * 100.0 / rated).round : nil,
      departments: department_counts(everything),
      department_field: department_field.present?
    }
  end

  def department_field
    return @department_field if defined?(@department_field)

    @department_field = ProjectCustomField.find_by(name: "Department")
  end

  # One query for every project's Department (instead of one lookup per
  # project per tab), resolved to the option's text for list fields.
  def department_by_project
    @department_by_project ||= begin
      raw = CustomValue.where(customized_type: "Project", custom_field_id: department_field.id)
                       .where.not(value: [nil, ""]).pluck(:customized_id, :value).to_h
      if department_field.field_format == "list"
        options = CustomOption.where(custom_field_id: department_field.id).pluck(:id, :value).to_h
        raw.transform_values { |v| options[v.to_i] }
      else
        raw
      end
    end
  end

  def department_counts(projects)
    return [] unless department_field

    projects
      .map { |p| department_by_project[p.id].presence || t("pmo_dashboard.department_unassigned") }
      .tally
      .sort_by { |name, n| [-n, name] }
  end
end


