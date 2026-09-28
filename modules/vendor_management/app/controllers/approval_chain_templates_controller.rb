class ApprovalChainTemplatesController < ApplicationController
  # Same reasoning as VendorManagementController -- no @project,
  # needs the global layout or the sidebar silently disappears.
  layout "global"

  before_action :require_login
  before_action :find_template
  before_action :require_vendor_management_approvals_manage
  before_action :find_step, only: %i[edit_step update_step destroy_step]

  no_authorization_required! :show, :new_step, :create_step, :edit_step, :update_step, :destroy_step

  menu_item :vendor_management

  def show
    @steps = @template.approval_step_definitions
  end

  def new_step
    @step = @template.approval_step_definitions.new(sequence: (@template.approval_step_definitions.maximum(:sequence) || 0) + 1)
  end

  def create_step
    @step = @template.approval_step_definitions.new(step_params)
    if @step.save
      redirect_to vendor_management_approval_chain_path, notice: t("vendor_management.notices.approval_step_created")
    else
      render :new_step
    end
  end

  def edit_step; end

  def update_step
    if @step.update(step_params)
      redirect_to vendor_management_approval_chain_path, notice: t("vendor_management.notices.approval_step_updated")
    else
      render :edit_step
    end
  end

  def destroy_step
    @step.destroy
    redirect_to vendor_management_approval_chain_path, notice: t("vendor_management.notices.approval_step_deleted")
  end

  private

  def find_template
    @template = VendorManagement::ApprovalChainTemplate.company_default
  end

  def find_step
    @step = @template.approval_step_definitions.find(params[:id])
  end

  def require_vendor_management_approvals_manage
    deny_access unless User.current.admin? || current_user_has_role?("Procurement Manager")
  end

  def current_user_has_role?(*names)
    User.current.memberships.any? { |m| m.roles.exists?(name: names) }
  end

  def step_params
    params.require(:approval_step_definition).permit(:sequence, :approver_title, :role_id)
  end
end
