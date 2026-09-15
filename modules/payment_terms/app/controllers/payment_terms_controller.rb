class PaymentTermsController < ApplicationController
  before_action :find_project, except: [:my_projects]
  before_action :authorize, except: [:my_projects]
  before_action :require_login, only: [:my_projects]

  # my_projects has no single @project to run the declarative `authorize`
  # check against -- it does its own per-row filtering via
  # Project.allowed_to(current_user, :view_payment_terms) instead.
  no_authorization_required! :my_projects

  before_action :find_line, only: %i[edit_line update_line destroy_line new_payment create_payment]
  before_action :find_payment, only: %i[edit_payment update_payment destroy_payment]

  menu_item :payment_terms

  def index
    @contract_lines = PaymentTerms::ContractLine.where(project: @project).includes(:payments).order(:name)
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
    project_ids = Project.allowed_to(current_user, :view_payment_terms).select(:id)
    @payments = PaymentTerms::Payment
                .joins(contract_line: :project)
                .where(payment_terms_contract_lines: { project_id: project_ids })
                .includes(:milestone, contract_line: :project)
                .order("projects.name, payment_terms_payments.expected_invoice_date")
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
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
