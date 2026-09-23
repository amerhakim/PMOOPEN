class VendorManagementMailer < UserMailer
  def po_needs_approval(user, purchase_order)
    @purchase_order = purchase_order

    open_project_headers "Project" => @purchase_order.project.identifier,
                         "Type" => "VendorManagement::PurchaseOrder"

    send_localized_mail(user) do
      "[#{@purchase_order.project.name}] #{t('vendor_management.notifications.po_needs_approval_subject', po_number: @purchase_order.po_number)}"
    end
  end

  def po_decision_made(user, purchase_order)
    @purchase_order = purchase_order

    open_project_headers "Project" => @purchase_order.project.identifier,
                         "Type" => "VendorManagement::PurchaseOrder"

    send_localized_mail(user) do
      "[#{@purchase_order.project.name}] #{t("vendor_management.notifications.po_decision_subject.#{@purchase_order.status}", po_number: @purchase_order.po_number)}"
    end
  end
end
