class PaymentTermsController < ApplicationController
  # Deliberately NOT `layout "global", only: :my_projects` -- Rails'
  # only:/except: layout conditions don't fall back to the superclass for
  # actions that don't match, they render with NO layout at all (hit this
  # exact trap once already on PmoDashboardController, see that
  # controller's own comment). Naming both cases explicitly avoids it.
  layout :payment_terms_layout

  before_action :find_project, except: %i[my_projects export_my_projects]
  before_action :authorize, except: %i[my_projects export_my_projects]
  before_action :require_login, only: %i[my_projects export_my_projects]

  # my_projects/export_my_projects have no single @project to run the
  # declarative `authorize` check against -- they do their own per-row
  # filtering via Project.allowed_to(current_user, :view_payment_terms)
  # instead.
  no_authorization_required! :my_projects, :export_my_projects

  before_action :find_line, only: %i[edit_line update_line destroy_line new_payment create_payment bulk_destroy_payments]
  before_action :find_payment, only: %i[edit_payment update_payment destroy_payment]

  menu_item :payment_terms

  def index
    @contract_lines = PaymentTerms::ContractLine.where(project: @project).order(:name)
    @can_edit = User.current.allowed_in_project?(:edit_payment_terms, @project)
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

  def export_my_projects
    @filters = {}
    assign_my_projects_data

    send_data PaymentTerms::MyProjectsExport.new(
      payments_by_project: @payments_by_project,
      o_and_ds: @o_and_ds,
      account_managers: @account_managers,
      project_managers: @project_managers
    ).call,
              filename: "pmo-projects-invoicing-details-#{Date.current.iso8601}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def payment_terms_layout
    action_name == "my_projects" ? "global" : "base"
  end

  # PMO Director (and admin) sees every project's invoices regardless of
  # membership -- everyone else only sees projects they actually belong to
  # with view_payment_terms, same as before.
  def pmo_director_or_admin?
    User.current.admin? || User.current.memberships.any? { |m| m.roles.exists?(name: "PMO Director") }
  end

  def visible_projects_for_my_projects
    if pmo_director_or_admin?
      Project.where(id: PaymentTerms::ContractLine.select(:project_id).distinct)
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
      :invoiced, :expected_invoice_month, :collected, :invoice_number, :invoice_month, :comments
    )
  end

  def find_project
    @project = Project.find(params[:project_id])
  end

  def filtered_payments_for(line)
    scope = line.payments.includes(:milestone).order(:id)
    f = payment_filter_params(line)

    scope = scope.where("payment_terms_payments.description ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:description])}%") if f[:description].present?
    scope = scope.where("payment_terms_payments.invoice_number ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:invoice_number])}%") if f[:invoice_number].present?
    scope = scope.where(invoiced: f[:invoiced]) if f[:invoiced].present?
    scope = scope.where(collected: f[:collected]) if f[:collected].present?

    if f[:milestone].present?
      scope = scope.joins(:milestone).where("work_packages.subject ILIKE ?", "%#{PaymentTerms::Payment.sanitize_sql_like(f[:milestone])}%")
    end

    scope
  end
  helper_method :filtered_payments_for

  def payment_filter_params(line)
    nested = params[:payment_q].is_a?(ActionController::Parameters) ? params[:payment_q][line.id.to_s] : nil
    nested.is_a?(ActionController::Parameters) ? nested.permit(:description, :milestone, :invoiced, :collected, :invoice_number) : {}
  end
  helper_method :payment_filter_params

  def find_line
    @contract_line = PaymentTerms::ContractLine.where(project: @project).find(params[:line_id])
  end

  def find_payment
    @payment = PaymentTerms::Payment.joins(:contract_line)
               .where(payment_terms_contract_lines: { project_id: @project.id })
               .find(params[:id])
  end

  def contract_line_params
    params.require(:contract_line).permit(:name, :component_value)
  end

  def payment_params
    params.require(:payment).permit(
      :description, :percent, :milestone_id, :expected_invoice_date,
      :invoiced, :invoice_number, :invoice_date, :collected, :comments
    )
  end

  def milestone_options
    @project.work_packages.where(type: Type.where(is_milestone: true)).order(:subject)
  end
end
