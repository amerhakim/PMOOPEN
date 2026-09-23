class PurchaseOrdersController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :find_purchase_order, only: %i[edit update destroy new_line_item create_line_item
                                                export_pdf update_delivery_status
                                                mark_all_delivered create_payment
                                                download_quotation_file destroy_quotation_file
                                                import_line_items_new import_line_items_create
                                                submit_for_approval]
  before_action :find_line_item, only: %i[edit_line_item update_line_item destroy_line_item]
  before_action :find_payment, only: %i[edit_payment update_payment destroy_payment]
  before_action :find_approval_step, only: %i[approve_step reject_step]

  def index
    @filters = filter_params
    @purchase_orders = filtered_purchase_orders
  end

  def bulk_destroy
    ids = Array(params[:purchase_order_ids]).reject(&:blank?)
    if ids.empty?
      redirect_to projects_vendor_management_purchase_orders_path(@project), alert: t("vendor_management.purchase_orders.no_pos_selected")
      return
    end

    count = VendorManagement::PurchaseOrder.where(project: @project, id: ids).destroy_all.size
    redirect_to projects_vendor_management_purchase_orders_path(@project), notice: t("vendor_management.purchase_orders.pos_deleted", count:)
  end

  def export_excel
    send_data VendorManagement::PurchaseOrderExport.new(@project).call,
              filename: "purchase-orders-#{@project.identifier}-#{Date.current.iso8601}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_new; end

  def import_create
    uploaded = params[:file]
    if uploaded.blank?
      redirect_to projects_import_new_vendor_management_purchase_orders_path(@project), alert: t("vendor_management.import.no_file")
      return
    end

    result = VendorManagement::PurchaseOrderImport.new(@project, uploaded.path).call
    flash[:notice] = t("vendor_management.import.summary", created: result.created.size, updated: result.updated.size)
    flash[:error] = result.errors.join(" | ") if result.errors.any?
    redirect_to projects_vendor_management_purchase_orders_path(@project)
  rescue StandardError => e
    redirect_to projects_import_new_vendor_management_purchase_orders_path(@project),
                alert: t("vendor_management.import.parse_error", message: e.message)
  end

  def export_pdf
    send_data VendorManagement::PurchaseOrderPdf.new(@purchase_order).call,
              filename: "#{@purchase_order.po_number.parameterize}.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def import_line_items_new; end

  def import_line_items_sample
    send_data VendorManagement::PoLineItemImport.sample_xlsx,
              filename: "line-items-import-sample.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_line_items_create
    uploaded = params[:file]
    if uploaded.blank?
      redirect_to projects_import_new_vendor_management_po_line_items_path(@project, @purchase_order), alert: t("vendor_management.import.no_file")
      return
    end

    result = VendorManagement::PoLineItemImport.new(@purchase_order, uploaded.path).call
    flash[:notice] = t("vendor_management.line_item_import.summary", created: result.created.size)
    flash[:error] = result.errors.join(" | ") if result.errors.any?
    redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order)
  rescue StandardError => e
    redirect_to projects_import_new_vendor_management_po_line_items_path(@project, @purchase_order),
                alert: t("vendor_management.import.parse_error", message: e.message)
  end

  # Saves both delivery checkboxes (QDS and Customer) for every line item
  # in one submit -- the PO-level Delivery QDS/Delivery to Customer
  # status recomputes automatically via PoLineItem's own after_save
  # callback, not set directly here.
  def update_delivery_status
    qds_ids = Array(params[:delivered_to_qds_ids]).map(&:to_i)
    customer_ids = Array(params[:delivered_to_customer_ids]).map(&:to_i)
    @purchase_order.po_line_items.find_each do |item|
      item.update!(
        delivered_to_qds: qds_ids.include?(item.id),
        delivered_to_customer: customer_ids.include?(item.id)
      )
    end
    redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                notice: t("vendor_management.notices.delivery_status_updated")
  end

  def mark_all_delivered
    target = params[:target] == "customer" ? :delivered_to_customer : :delivered_to_qds
    @purchase_order.po_line_items.find_each { |item| item.update!(target => true) }
    redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                notice: t("vendor_management.notices.all_marked_delivered")
  end

  def create_payment
    payment = @purchase_order.po_payments.new(payment_params)
    if payment.save
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.payment_added")
    else
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  alert: payment.errors.full_messages.join(", ")
    end
  end

  def edit_payment; end

  def update_payment
    if @payment.update(payment_params)
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @payment.purchase_order),
                  notice: t("vendor_management.notices.payment_updated")
    else
      render :edit_payment
    end
  end

  def destroy_payment
    @payment.destroy
    redirect_to projects_edit_vendor_management_purchase_order_path(@project, @payment.purchase_order),
                notice: t("vendor_management.notices.payment_removed")
  end

  def download_quotation_file
    return deny_access unless @purchase_order.quotation_file_attached?

    send_data @purchase_order.quotation_file_data,
              filename: @purchase_order.quotation_file_filename,
              type: @purchase_order.quotation_file_content_type,
              disposition: "inline"
  end

  def destroy_quotation_file
    @purchase_order.remove_quotation_file!
    redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                notice: t("vendor_management.notices.quotation_file_removed")
  end

  def submit_for_approval
    if @purchase_order.submit_for_approval!
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.po_submitted")
    else
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  alert: t("vendor_management.notices.po_submit_failed_no_chain")
    end
  end

  def approve_step
    if @purchase_order.approve_step!(@approval_step, User.current.name)
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.step_approved")
    else
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  alert: t("vendor_management.notices.step_out_of_sequence")
    end
  end

  def reject_step
    if @purchase_order.reject_step!(@approval_step, User.current.name)
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.step_rejected")
    else
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  alert: t("vendor_management.notices.step_out_of_sequence")
    end
  end

  def new
    @purchase_order = VendorManagement::PurchaseOrder.new
    @vendors = VendorManagement::Vendor.order(:name)
  end

  def create
    @purchase_order = VendorManagement::PurchaseOrder.new(purchase_order_params.merge(project: @project))
    if @purchase_order.save
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.po_created")
    else
      @vendors = VendorManagement::Vendor.order(:name)
      render :new
    end
  end

  def edit
    @vendors = VendorManagement::Vendor.order(:name)
  end

  def update
    if @purchase_order.update(purchase_order_params)
      redirect_to projects_vendor_management_purchase_orders_path(@project),
                  notice: t("vendor_management.notices.po_updated")
    else
      @vendors = VendorManagement::Vendor.order(:name)
      render :edit
    end
  end

  def destroy
    @purchase_order.destroy
    redirect_to projects_vendor_management_purchase_orders_path(@project),
                notice: t("vendor_management.notices.po_deleted")
  end

  def new_line_item
    @line_item = @purchase_order.po_line_items.new
  end

  def create_line_item
    @line_item = @purchase_order.po_line_items.new(line_item_params)
    if @line_item.save
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @purchase_order),
                  notice: t("vendor_management.notices.line_item_created")
    else
      render :new_line_item
    end
  end

  def edit_line_item; end

  def update_line_item
    if @line_item.update(line_item_params)
      redirect_to projects_edit_vendor_management_purchase_order_path(@project, @line_item.purchase_order),
                  notice: t("vendor_management.notices.line_item_updated")
    else
      render :edit_line_item
    end
  end

  def destroy_line_item
    purchase_order = @line_item.purchase_order
    @line_item.destroy
    redirect_to projects_edit_vendor_management_purchase_order_path(purchase_order.project, purchase_order),
                notice: t("vendor_management.notices.line_item_deleted")
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def find_purchase_order
    @purchase_order = VendorManagement::PurchaseOrder.where(project: @project).find(params[:po_id])
  end

  def find_line_item
    @line_item = VendorManagement::PoLineItem.joins(:purchase_order)
                 .where(vendor_management_purchase_orders: { project_id: @project.id })
                 .find(params[:id])
  end

  def find_payment
    @payment = VendorManagement::PoPayment.joins(:purchase_order)
               .where(vendor_management_purchase_orders: { project_id: @project.id })
               .find(params[:id])
  end

  def find_approval_step
    @approval_step = VendorManagement::PoApprovalStep.joins(:purchase_order)
                     .where(vendor_management_purchase_orders: { project_id: @project.id })
                     .find(params[:id])
    @purchase_order = @approval_step.purchase_order
  end

  def can_edit?
    User.current.allowed_in_project?(:edit_vendor_management, @project)
  end
  helper_method :can_edit?

  def can_manage_approvals?
    User.current.allowed_in_project?(:manage_vendor_management_approvals, @project)
  end
  helper_method :can_manage_approvals?

  def filtered_purchase_orders
    scope = VendorManagement::PurchaseOrder.where(project: @project).includes(:vendor, :po_line_items).order(:po_number)

    f = filter_params
    scope = scope.where("po_number ILIKE ?", "%#{VendorManagement::PurchaseOrder.sanitize_sql_like(f[:po_number])}%") if f[:po_number].present?
    scope = scope.where(vendor_id: f[:vendor_id]) if f[:vendor_id].present?
    scope = scope.where(currency: f[:currency]) if f[:currency].present?
    scope = scope.where(status: f[:status]) if f[:status].present?
    scope = scope.where(delivery_status_qds: f[:delivery_status_qds]) if f[:delivery_status_qds].present?
    scope = scope.where(delivery_status_customer: f[:delivery_status_customer]) if f[:delivery_status_customer].present?

    case f[:payment_status]
    when "not_invoiced" then scope = scope.where(total_paid: 0)
    when "paid" then scope = scope.where("remaining_in_po <= 0")
    when "partially_paid" then scope = scope.where("total_paid > 0 AND remaining_in_po > 0")
    end

    scope
  end

  def filter_params
    params.fetch(:q, {}).permit(:po_number, :vendor_id, :currency, :status, :delivery_status_qds, :delivery_status_customer, :payment_status)
  end

  def purchase_order_params
    permitted = params.require(:purchase_order).permit(
      :vendor_id, :po_number, :o_and_d, :quotation_ref_no, :order_description, :issue_date, :currency, :status,
      :total_value, :expected_end_date, :payment_terms, :special_note, :is_non_cancellable,
      :end_user_name, :end_user_address, :end_user_contact_name,
      :end_user_contact_phone, :end_user_contact_email,
      :incoterm, :delivery_address, :delivery_contact, :quotation_file
    )
    # total_value is only ever hand-entered for a PO with no line items yet
    # (matching PurchaseOrderImport's own carve-out) -- once real line
    # items exist, PoLineItem's own recompute callback owns this column,
    # so a stray submitted value must not be allowed to clobber it.
    permitted.delete(:total_value) if @purchase_order&.po_line_items&.exists?
    permitted
  end

  def payment_params
    params.require(:po_payment).permit(:amount, :paid_on, :invoice_no, :description, :note)
  end

  def line_item_params
    params.require(:po_line_item).permit(:part_no, :description, :item_type, :quantity, :unit_price, :start_date, :end_date, :section_label)
  end
end



