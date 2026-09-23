class PoTemplatesController < ApplicationController
  # Same reasoning as VendorManagementController/ApprovalChainTemplatesController
  # -- no @project, needs the global layout or the sidebar disappears.
  layout "global"

  before_action :require_login
  before_action :find_template
  before_action :require_vendor_management_templates_manage

  no_authorization_required! :edit, :update, :designer, :update_layout, :preview

  menu_item :vendor_management

  def edit; end

  def update
    if @template.update(template_params)
      redirect_to vendor_management_po_template_path, notice: t("vendor_management.notices.po_template_updated")
    else
      render :edit
    end
  end

  def designer
    @default_layout = VendorManagement::PoTemplate::DEFAULT_LAYOUT
  end

  def update_layout
    layout = JSON.parse(params.require(:layout_json))
    if @template.update(layout:)
      redirect_to designer_vendor_management_po_template_path, notice: t("vendor_management.notices.po_template_updated")
    else
      redirect_to designer_vendor_management_po_template_path, alert: @template.errors.full_messages.join(", ")
    end
  rescue JSON::ParserError, ActionController::ParameterMissing
    redirect_to designer_vendor_management_po_template_path, alert: t("vendor_management.po_template.invalid_layout")
  end

  # Renders a real export so "Preview PDF" on the designer shows exactly
  # what an actual export looks like -- uses whichever PO was most
  # recently updated (whatever the user is most likely already looking
  # at), since the template is one shared, global layout, not tied to
  # any specific PO.
  def preview
    po = VendorManagement::PurchaseOrder.order(updated_at: :desc).first
    if po.nil?
      redirect_to designer_vendor_management_po_template_path, alert: t("vendor_management.po_template.no_po_for_preview")
      return
    end

    send_data VendorManagement::PurchaseOrderPdf.new(po).call,
              filename: "po-template-preview.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  private

  def find_template
    @template = VendorManagement::PoTemplate.current
  end

  def require_vendor_management_templates_manage
    deny_access unless User.current.admin? || current_user_has_role?("Procurement Manager", "PMO Director")
  end

  def current_user_has_role?(*names)
    User.current.memberships.any? { |m| m.roles.exists?(name: names) }
  end

  def template_params
    params.require(:po_template).permit(:header_text, :header_text_ar, :footer_text)
  end
end

