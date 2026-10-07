class DeliveryNotesController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :find_note, only: %i[download destroy]

  menu_item :vendor_management_delivery_notes

  def index
    @can_edit = can_edit?
    @purchase_orders = VendorManagement::PurchaseOrder.where(project: @project).order(:po_number).to_a
    @notes = VendorManagement::DeliveryNote.without_data.where(project: @project)
                                           .includes(:purchase_order, :uploaded_by).order(created_at: :desc).to_a
    with_notes = @notes.filter_map(&:purchase_order_id).uniq
    @pos_with_notes = @purchase_orders.count { |po| with_notes.include?(po.id) }
    @delivered_without_note = @purchase_orders.count do |po|
      !with_notes.include?(po.id) && (po.delivery_status_qds != "not_delivered" || po.delivery_status_customer != "not_delivered")
    end
  end

  def create
    return deny_access unless can_edit?

    files = Array(params[:files]).select { |f| f.respond_to?(:original_filename) }
    po = params[:purchase_order_id].presence && VendorManagement::PurchaseOrder.where(project: @project).find(params[:purchase_order_id])
    if files.empty?
      redirect_to back_path(po), alert: t("vendor_management.delivery_notes.no_files")
      return
    end

    saved = 0
    errors = []
    files.each do |file|
      note = VendorManagement::DeliveryNote.from_upload(file, project: @project, purchase_order: po, user: User.current)
      if note.save
        saved += 1
      else
        errors << "#{file.original_filename}: #{note.errors.full_messages.to_sentence}"
      end
    end

    flash[:notice] = t("vendor_management.delivery_notes.uploaded", count: saved) if saved.positive?
    flash[:error] = errors.join(" | ") if errors.any?
    redirect_to back_path(po)
  end

  def download
    send_data @note.data, filename: @note.filename, type: @note.content_type.presence || "application/octet-stream", disposition: "attachment"
  end

  def destroy
    return deny_access unless can_edit?

    po = @note.purchase_order
    @note.destroy
    flash[:notice] = t("vendor_management.delivery_notes.deleted")
    redirect_to back_path(po)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def find_note
    @note = VendorManagement::DeliveryNote.where(project: @project).find(params[:id])
  end

  def can_edit?
    User.current.allowed_in_project?(:edit_vendor_management, @project)
  end
  helper_method :can_edit?

  # Uploads started from a PO page return there; the project page returns to itself.
  def back_path(po)
    if params[:return_to] == "po" && po
      projects_edit_vendor_management_purchase_order_path(@project, po)
    else
      projects_vendor_management_delivery_notes_path(@project)
    end
  end
end
