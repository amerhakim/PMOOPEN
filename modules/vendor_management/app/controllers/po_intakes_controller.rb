class PoIntakesController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :find_import, only: %i[show confirm destroy]

  MAX_FILE_SIZE = 25.megabytes

  def new; end

  def create
    uploaded = params[:file]
    kind = uploaded && VendorManagement::PoIntake.kind_for(uploaded.original_filename)
    if kind.nil?
      redirect_to projects_new_vendor_management_po_intake_path(@project), alert: t("vendor_management.po_ai.unsupported_file")
      return
    end
    if uploaded.size > MAX_FILE_SIZE
      redirect_to projects_new_vendor_management_po_intake_path(@project), alert: t("vendor_management.po_ai.file_too_big")
      return
    end

    import = VendorManagement::PoIntake.create!(
      project: @project, user: User.current, source_kind: kind, source_filename: uploaded.original_filename,
      source_content_type: uploaded.content_type, source_data: uploaded.read, stage: "Waiting to start"
    )
    VendorManagement::ProcessPoIntakeJob.perform_later(import.id)
    redirect_to projects_vendor_management_po_intake_path(@project, import)
  end

  def show
    return unless @import.status == "ready"

    @result = @import.result_data
    @vendors = VendorManagement::Vendor.order(:name)
  end

  def confirm
    return redirect_to(projects_vendor_management_po_intake_path(@project, @import)) unless @import.status == "ready"

    outcome = VendorManagement::PoReader::Creator.new(import: @import, user: User.current, form: params[:pos]&.to_unsafe_h).call
    @import.update_columns(status: "confirmed", updated_at: Time.current) if outcome.errors.empty? && outcome.created.any?

    flash[:notice] = t("vendor_management.po_ai.created", count: outcome.created.size) if outcome.created.any?
    flash[:error] = outcome.errors.join(" | ") if outcome.errors.any?
    if outcome.created.size == 1 && outcome.errors.empty?
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, outcome.created.first)
    elsif outcome.errors.any?
      redirect_to projects_vendor_management_po_intake_path(@project, @import)
    else
      redirect_to projects_vendor_management_purchase_orders_path(@project)
    end
  end

  def destroy
    @import.destroy
    redirect_to projects_vendor_management_purchase_orders_path(@project)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def find_import
    @import = VendorManagement::PoIntake.where(project: @project).find(params[:id])
  end
end
