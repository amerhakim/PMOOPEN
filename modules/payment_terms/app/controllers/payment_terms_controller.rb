class PaymentTermsController < ApplicationController
  # Deliberately NOT `layout "global", only: :my_projects` -- Rails'
  # only:/except: layout conditions don't fall back to the superclass for
  # actions that don't match, they render with NO layout at all (hit this
  # exact trap once already on PmoDashboardController, see that
  # controller's own comment). Naming both cases explicitly avoids it.
  layout :payment_terms_layout

  before_action :find_project, except: %i[my_projects export_my_projects analytics archived]
  before_action :authorize, except: %i[my_projects export_my_projects analytics archived]
  before_action :require_login, only: %i[my_projects export_my_projects analytics archived]

  # my_projects/export_my_projects/analytics have no single @project to run
  # the declarative `authorize` check against -- they do their own per-row
  # filtering via Project.allowed_to(current_user, :view_payment_terms) (or,
  # for analytics, real Project Manager role membership) instead.
  no_authorization_required! :my_projects, :export_my_projects, :analytics, :archived

  before_action :find_line, only: %i[edit_line update_line destroy_line new_payment create_payment bulk_destroy_payments]
  before_action :find_payment, only: %i[edit_payment update_payment destroy_payment]

  menu_item :payment_terms
  # The global sidebar highlights the item named here -- without these two,
  # the Analytics and Archived pages kept "Project Invoices" selected.
  menu_item :payment_terms_analytics, only: :analytics
  menu_item :payment_terms_archived, only: :archived

  def index
    @contract_lines = PaymentTerms::ContractLine.where(project: @project).order(:name).includes(payments: :milestone)
    @can_edit = User.current.allowed_in_project?(:edit_payment_terms, @project)
    @kpis = payment_kpi_totals_by_currency(@contract_lines)
  end

  def bulk_destroy_payments
    return deny_access unless User.current.allowed_in_project?(:edit_payment_terms, @project)

    ids = Array(params[:payment_ids]).reject(&:blank?)
    if ids.empty?
      redirect_to projects_payment_terms_path(@project), alert: t("payment_terms.index.no_payments_selected")
      return
    end

    count = @contract_line.payments.where(id: ids).destroy_all.size
    redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.index.payments_deleted", count:)
  end

  def new_line
    @contract_line = PaymentTerms::ContractLine.new
  end

  def create_line
    @contract_line = PaymentTerms::ContractLine.new(contract_line_params.merge(project: @project))
    if @contract_line.save
      redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.notices.line_created")
    else
      render :new_line
    end
  end

  def edit_line; end

  def update_line
    if @contract_line.update(contract_line_params)
      redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.notices.line_updated")
    else
      render :edit_line
    end
  end

  def destroy_line
    @contract_line.destroy
    redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.notices.line_deleted")
  end

  def new_payment
    @payment = @contract_line.payments.new
    @milestones = milestone_options
  end

  def create_payment
    @payment = @contract_line.payments.new(payment_params)
    if @payment.save
      redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.notices.payment_created")
    else
      @milestones = milestone_options
      render :new_payment
    end
  end

  def edit_payment
    @contract_line = @payment.contract_line
    @milestones = milestone_options
  end

  def update_payment
    @contract_line = @payment.contract_line
    if @payment.update(payment_params)
      redirect_to projects_payment_terms_path(@project), notice: t("payment_terms.notices.payment_updated")
    else
      @milestones = milestone_options
      render :edit_payment
    end
  end

  def destroy_payment
    project = @payment.project
    @payment.destroy
    redirect_to projects_payment_terms_path(project), notice: t("payment_terms.notices.payment_deleted")
  end

  def my_projects
    @filters = my_projects_filter_params
    assign_my_projects_data
  end

  # Same table as my_projects, but for archived (closed) projects only --
  # they are kept off the live report and the dashboard cards, and this is
  # where their payment history lives.
  def archived
    @archived_view = true
    @filters = my_projects_filter_params
    assign_my_projects_data
    render :my_projects
  end

  # A richer, chart-driven analytics view over the same underlying data as
  # my_projects, tab-scoped by Project Manager: a PMO Director (or admin)
  # sees an "All Projects" tab plus one tab per real Project Manager found
  # across every project with payment terms data; anyone else sees a single
  # tab scoped to the projects where THEY hold the Project Manager role.
  # Everything (KPIs, charts, rankings, table) is computed once per tab
  # here and rendered as plain server-side HTML/inline SVG -- no chart
  # library, no client requests after load, so switching tabs or years is
  # instant.
  def analytics
    is_director = pmo_director_or_admin?
    @currencies = PaymentTerms::ContractLine.distinct.pluck(:currency).sort
    @currencies = ["QAR"] if @currencies.empty?
    @analytics_currency = params[:currency].presence_in(@currencies) || (@currencies.include?("QAR") ? "QAR" : @currencies.first)

    # Only projects that actually bill in the selected currency -- QAR and
    # SAR figures are never summed together.
    in_currency = PaymentTerms::ContractLine.where(currency: @analytics_currency).select(:project_id).distinct
    projects = Project.where(id: in_currency).to_a
    pm_by_project = project_manager_members_by_project(projects)

    @scopes =
      if is_director
        pm_users = pm_by_project.values.flatten(1).uniq.sort_by { |_, name| name }
        [{ key: "all", label: t("payment_terms.analytics.all_projects_tab"), projects: projects }] +
          pm_users.map do |user_id, name|
            ids = pm_by_project.select { |_, members| members.any? { |uid, _| uid == user_id } }.keys
            { key: "pm-#{user_id}", label: name, projects: projects.select { |p| ids.include?(p.id) } }
          end
      else
        ids = pm_by_project.select { |_, members| members.any? { |uid, _| uid == User.current.id } }.keys
        [{ key: "mine", label: t("payment_terms.analytics.my_projects_tab"), projects: projects.select { |p| ids.include?(p.id) } }]
      end
    @scopes = @scopes.select { |s| s[:key] == "all" || s[:key] == "mine" || s[:projects].any? }

    account_managers = bulk_custom_field_values(projects, "Account Manager")

    @scopes.each do |scope|
      active, archived = scope[:projects].partition(&:active?)
      scope[:data] = build_analytics_scope_data(active, pm_by_project, account_managers, archived)
    end
    @has_any_scope_data = @scopes.any? { |s| s[:projects].any? }
  end

  def export_my_projects
    @filters = {}
    @archived_view = params[:archived].present?
    assign_my_projects_data

    send_data PaymentTerms::MyProjectsExport.new(
      payments_by_project: @payments_by_project,
      o_and_ds: @o_and_ds,
      account_managers: @account_managers,
      project_managers: @project_managers
    ).call,
              filename: "pmo-#{@archived_view ? 'archived-projects' : 'projects'}-invoicing-details-#{Date.current.iso8601}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def payment_terms_layout
    %w[my_projects analytics archived].include?(action_name) ? "global" : "base"
  end

  # PMO Director (and admin) sees every project's invoices regardless of
  # membership -- everyone else only sees projects they actually belong to
  # with view_payment_terms, same as before.
  def pmo_director_or_admin?
    User.current.admin? || User.current.memberships.any? { |m| m.roles.exists?(name: "PMO Director") }
  end

  # Live projects for the main report, archived ones for #archived.
  # Archived projects drop out of Project.allowed_to (OpenProject hides
  # them from normal membership scopes), so a non-director reaches theirs
  # through their Project/Program Manager membership instead.
  def visible_projects_for_my_projects
    with_data = PaymentTerms::ContractLine.select(:project_id).distinct

    if @archived_view
      archived = Project.where(active: false, id: with_data)
      return archived if pmo_director_or_admin?

      managed = Member.joins(:roles)
                      .where(user_id: User.current.id, roles: { name: PaymentTerms::CreateInvoiceOverdueNotificationsJob::MANAGER_ROLE_NAMES })
                      .select(:project_id)
      archived.where(id: managed)
    elsif pmo_director_or_admin?
      Project.where(active: true, id: with_data)
    else
      Project.allowed_to(current_user, :view_payment_terms)
    end
  end

  # Shared by my_projects (respects @filters) and export_my_projects
  # (@filters is always {} there, so this only ever applies role-scoping,
  # never the on-screen text filters -- matches VendorExport's own
  # "export everything visible, ignore the page's filter state" behavior).
  # Dropdown option lists are built from the full role-scoped project set
  # BEFORE @filters narrows it, so choosing one filter never removes
  # options from another filter's own dropdown.
  def assign_my_projects_data
    base_projects = visible_projects_for_my_projects.to_a
    @account_managers = bulk_custom_field_values(base_projects, "Account Manager")
    @o_and_ds = bulk_custom_field_values(base_projects, "O&D")
    @project_managers = bulk_project_managers(base_projects)
    project_names = base_projects.index_by(&:id).transform_values(&:name)

    @project_options = project_names.values.uniq.sort
    @account_manager_options = @account_managers.values.compact.uniq.sort
    @project_manager_options = @project_managers.values.flatten.compact.uniq.sort

    visible_project_ids = base_projects.map(&:id)
    visible_project_ids = filter_ids_by_text(visible_project_ids, project_names, @filters[:project])
    visible_project_ids = filter_ids_by_text(visible_project_ids, @o_and_ds, @filters[:o_and_d])
    visible_project_ids = filter_ids_by_text(visible_project_ids, @account_managers, @filters[:account_manager])
    visible_project_ids = filter_ids_by_text(visible_project_ids, @project_managers, @filters[:project_manager])

    payments = PaymentTerms::Payment
               .joins(contract_line: :project)
               .where(payment_terms_contract_lines: { project_id: visible_project_ids })
               .includes(:milestone, contract_line: :project)
               .order("projects.name, payment_terms_payments.expected_invoice_date")
    payments = apply_my_projects_payment_filters(payments, @filters)

    @payments_by_project = payments.group_by(&:project)
  end

  # One query per custom field across every visible project, instead of
  # one query per project (this report used to call a per-project helper
  # for Account Manager -- and, after this session's own Project Manager
  # addition, a second one -- for every row, which is the kind of N+1
  # that gets slow as soon as there's more than a handful of projects).
  def bulk_custom_field_values(projects, field_name)
    field = ProjectCustomField.find_by(name: field_name)
    return {} if field.nil? || projects.empty?

    CustomValue
      .where(customized_type: "Project", custom_field_id: field.id, customized_id: projects.map(&:id))
      .pluck(:customized_id, :value)
      .to_h
  end

  # Same reasoning as bulk_custom_field_values, but Project Manager is a
  # role membership, not a custom field.
  def bulk_project_managers(projects)
    return {} if projects.empty?

    members = Member.joins(:roles)
                     .where(project_id: projects.map(&:id), roles: { name: "Project Manager" })
                     .includes(:principal)
                     .distinct

    members.each_with_object(Hash.new { |h, k| h[k] = [] }) do |member, hash|
      hash[member.project_id] << member.principal.name
    end
  end

  # Same lookup as bulk_project_managers, but keyed by user id (not just
  # name) so #analytics can reliably tell two same-named users apart and
  # match the CURRENT user against it -- matching on a plain display name
  # would be fragile.
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

  # One tab's worth of computed data for #analytics: portfolio KPIs, the
  # collection funnel and "collection status" split (both scoped to
  # payments due by the end of the current month, never the far future),
  # this month's own figures, a per-project ranking with an inline
  # collected/issued/not-yet-invoiced breakdown, a project-manager/
  # account-manager breakdown (account-manager only meaningful for the
  # "all" scope), a closed/archived-projects summary, the full detail
  # table, and every year's monthly series pre-computed up front (so the
  # page's own year-nav buttons never need another request).
  def build_analytics_scope_data(projects, pm_by_project, account_managers, archived_projects = [])
    payments = live_payments_for(projects)

    total = payments.sum { |p| p.value.to_f }
    collected = payments.select(&:collected?).sum { |p| p.value.to_f }
    invoiced_awaiting = payments.select { |p| p.invoiced? && !p.collected? }.sum { |p| p.value.to_f }
    not_invoiced = payments.reject(&:invoiced?).sum { |p| p.value.to_f }

    month_end = Date.current.end_of_month
    due_payments = payments.select { |p| p.expected_invoice_date.present? && p.expected_invoice_date <= month_end }
    due_total = due_payments.sum { |p| p.value.to_f }
    due_invoiced = due_payments.select(&:invoiced?).sum { |p| p.value.to_f }
    due_collected = due_payments.select(&:collected?).sum { |p| p.value.to_f }
    overdue_payments = due_payments.reject(&:invoiced?)

    this_month_payments = payments.select do |p|
      p.expected_invoice_date&.year == Date.current.year && p.expected_invoice_date&.month == Date.current.month
    end
    this_month = {
      total: this_month_payments.sum { |p| p.value.to_f },
      issued: this_month_payments.select(&:invoiced?).sum { |p| p.value.to_f },
      collected: this_month_payments.select(&:collected?).sum { |p| p.value.to_f }
    }

    monthly_by_year = Hash.new { |h, k| h[k] = Array.new(12) { { total: 0.0, issued: 0.0, collected: 0.0 } } }
    payments.each do |p|
      next if p.expected_invoice_date.blank?

      bucket = monthly_by_year[p.expected_invoice_date.year][p.expected_invoice_date.month - 1]
      bucket[:total] += p.value.to_f
      bucket[:issued] += p.value.to_f if p.invoiced?
      bucket[:collected] += p.value.to_f if p.collected?
    end
    monthly_by_year[Date.current.year] ||= Array.new(12) { { total: 0.0, issued: 0.0, collected: 0.0 } }

    by_project = projects.map do |pr|
      pr_payments = payments.select { |p| p.contract_line.project_id == pr.id }
      {
        project: pr,
        pm_names: (pm_by_project[pr.id] || []).map(&:last),
        am: account_managers[pr.id],
        total: pr_payments.sum { |p| p.value.to_f },
        collected: pr_payments.select(&:collected?).sum { |p| p.value.to_f },
        invoiced_awaiting: pr_payments.select { |p| p.invoiced? && !p.collected? }.sum { |p| p.value.to_f },
        not_invoiced: pr_payments.reject(&:invoiced?).sum { |p| p.value.to_f }
      }
    end.sort_by { |h| -h[:total] }

    by_account_manager = payments.group_by { |p| account_managers[p.contract_line.project_id].presence || "(unassigned)" }
                                  .transform_values { |ps| ps.sum { |p| p.value.to_f } }
                                  .sort_by { |_, v| -v }

    by_project_manager = payments.group_by { |p| (pm_by_project[p.contract_line.project_id] || []).map(&:last).first.presence || "(unassigned)" }
                                  .transform_values { |ps| ps.sum { |p| p.value.to_f } }
                                  .sort_by { |_, v| -v }

    archived = build_archived_data(archived_projects, pm_by_project)

    {
      payment_count: payments.size, project_count: projects.size,
      total:, collected:, invoiced_awaiting:, not_invoiced:,
      overdue_count: overdue_payments.size, overdue_total: overdue_payments.sum { |p| p.value.to_f },
      due_total:, due_invoiced:, due_collected:,
      this_month:, monthly_by_year:, by_project:, by_account_manager:, by_project_manager:, archived:
    }
  end

  # Live (not cancelled) payments of the given projects, in the
  # currency currently selected on the analytics page. Negative rows are
  # credits/discounts and net off naturally in every sum.
  def live_payments_for(projects)
    ids = projects.map(&:id)
    return [] if ids.empty?

    PaymentTerms::Payment.live
                         .joins(contract_line: :project)
                         .where(payment_terms_contract_lines: { project_id: ids, currency: @analytics_currency })
                         .includes(:contract_line)
                         .to_a
  end

  # Collection funnel for archived projects, kept apart from the live
  # numbers so ~2 years of settled history doesn't distort forecasts. An
  # archived project is supposed to be fully collected, so any open balance
  # here is a warning, not a forecast.
  def build_archived_data(projects, pm_by_project)
    payments = live_payments_for(projects)
    total = payments.sum { |p| p.value.to_f }
    collected = payments.select(&:collected?).sum { |p| p.value.to_f }
    invoiced_awaiting = payments.select { |p| p.invoiced? && !p.collected? }.sum { |p| p.value.to_f }
    not_invoiced = payments.reject(&:invoiced?).sum { |p| p.value.to_f }
    by_id = projects.index_by(&:id)

    open_projects = payments.reject(&:collected?).group_by { |p| p.contract_line.project_id }.map do |project_id, rows|
      { project: by_id[project_id], pm_names: (pm_by_project[project_id] || []).map(&:last),
        amount: rows.sum { |p| p.value.to_f }, invoiced_awaiting: rows.select(&:invoiced?).sum { |p| p.value.to_f } }
    end.sort_by { |h| -h[:amount] }

    {
      project_count: payments.map { |p| p.contract_line.project_id }.uniq.size,
      payment_count: payments.size,
      total:, collected:, invoiced_awaiting:, not_invoiced:,
      open_balance: invoiced_awaiting + not_invoiced,
      open_projects:
    }
  end

  def filter_ids_by_text(ids, lookup, value)
    return ids if value.blank?

    needle = value.downcase
    ids.select { |id| lookup[id].to_s.downcase.include?(needle) }
  end

  def apply_my_projects_payment_filters(scope, f)
    scope = scope.where("payment_terms_payments.description ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:description])}%") if f[:description].present?
    scope = scope.where("payment_terms_payments.invoice_number ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:invoice_number])}%") if f[:invoice_number].present?
    scope = scope.where("payment_terms_payments.comments ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:comments])}%") if f[:comments].present?
    scope = scope.where(invoiced: f[:invoiced]) if f[:invoiced].present?
    scope = scope.where(collected: f[:collected]) if f[:collected].present?
    scope = scope.where(value: f[:value].to_f) if f[:value].present?

    expected_range = month_range(f[:expected_invoice_month])
    scope = scope.where(expected_invoice_date: expected_range) if expected_range

    invoice_range = month_range(f[:invoice_month])
    scope = scope.where(invoice_date: invoice_range) if invoice_range

    expected_collection_range = month_range(f[:expected_collection_month])
    scope = scope.where(expected_collection_date: expected_collection_range) if expected_collection_range

    actual_collection_range = month_range(f[:actual_collection_month])
    scope = scope.where(actual_collection_date: actual_collection_range) if actual_collection_range

    scope
  end

  # "YYYY-MM" (from an <input type="month">) -> the full date range for
  # that month, so the filter matches by month only, not an exact day.
  def month_range(yyyymm)
    return nil if yyyymm.blank?

    year, month = yyyymm.split("-").map(&:to_i)
    Date.new(year, month, 1)..Date.new(year, month, -1)
  rescue ArgumentError, Date::Error
    nil
  end

  def my_projects_filter_params
    params.fetch(:q, {}).permit(
      :project, :o_and_d, :account_manager, :project_manager, :description, :value,
      :invoiced, :expected_invoice_month, :collected, :expected_collection_month, :actual_collection_month,
      :invoice_number, :invoice_month, :comments
    )
  end

  def find_project
    @project = Project.find(params[:project_id])
  end

  # Project-wide totals for the KPI summary bar -- always computed from
  # every payment on every line, never affected by the page's own
  # client-side filter bar (that filter only hides/shows rows, it doesn't
  # change what "the real numbers" are).
  def payment_kpi_totals_by_currency(contract_lines)
    grouped = contract_lines.group_by(&:currency)
    grouped = { "QAR" => [] } if grouped.empty?
    grouped.transform_values { |lines| payment_kpi_totals(lines) }
  end

  # Cancelled (descoped) payments are excluded from every total.
  def payment_kpi_totals(contract_lines)
    payments = contract_lines.flat_map(&:payments).reject(&:cancelled?)

    {
      contract_value: contract_lines.sum { |line| line.component_value.to_f },
      collected: payments.select(&:collected?).sum { |p| p.value.to_f },
      invoiced_awaiting: payments.select { |p| p.invoiced? && !p.collected? }.sum { |p| p.value.to_f },
      not_yet_invoiced: payments.reject(&:invoiced?).sum { |p| p.value.to_f }
    }
  end

  def find_line
    @contract_line = PaymentTerms::ContractLine.where(project: @project).find(params[:line_id])
  end

  def find_payment
    @payment = PaymentTerms::Payment.joins(:contract_line)
               .where(payment_terms_contract_lines: { project_id: @project.id })
               .find(params[:id])
  end

  def contract_line_params
    params.require(:contract_line).permit(:name, :component_value, :currency)
  end

  def payment_params
    params.require(:payment).permit(
      :description, :percent, :value, :entered_field, :milestone_id, :expected_invoice_date,
      :invoiced, :invoice_number, :invoice_date, :collected, :expected_collection_date, :actual_collection_date, :cancelled, :comments
    )
  end

  def milestone_options
    @project.work_packages.where(type: Type.where(is_milestone: true)).order(:subject)
  end
end


