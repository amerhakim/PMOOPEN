Rails.application.routes.draw do
  get    "vendor_management/vendors",          to: "vendor_management#index",   as: "vendor_management_vendors"
  get    "vendor_management/vendors/new",      to: "vendor_management#new",     as: "new_vendor_management_vendor"
  post   "vendor_management/vendors",          to: "vendor_management#create",  as: "vendor_management_vendors_create"
  get    "vendor_management/vendors/:id/edit", to: "vendor_management#edit",    as: "edit_vendor_management_vendor"
  patch  "vendor_management/vendors/:id",      to: "vendor_management#update",  as: "vendor_management_vendor"
  delete "vendor_management/vendors/:id",      to: "vendor_management#destroy", as: "vendor_management_vendor_destroy"

  post   "vendor_management/vendors/bulk_destroy",      to: "vendor_management#bulk_destroy", as: "bulk_destroy_vendor_management_vendors"

  get    "vendor_management/vendors/export",           to: "vendor_management#export",       as: "export_vendor_management_vendors"
  get    "vendor_management/vendors/import/new",       to: "vendor_management#import_new",   as: "import_new_vendor_management_vendors"
  post   "vendor_management/vendors/import",            to: "vendor_management#import_create", as: "import_vendor_management_vendors"

  get    "vendor_management/purchase_orders",                     to: "purchase_orders_overview#index",  as: "vendor_management_purchase_orders_overview"
  get    "vendor_management/purchase_orders/new",                 to: "purchase_orders_overview#new",    as: "new_vendor_management_purchase_order_overview"
  post   "vendor_management/purchase_orders",                     to: "purchase_orders_overview#create", as: "vendor_management_purchase_orders_overview_create"

  get    "vendor_management/po_template/edit",                  to: "po_templates#edit",                     as: "edit_vendor_management_po_template"
  patch  "vendor_management/po_template",                       to: "po_templates#update",                   as: "vendor_management_po_template"
  get    "vendor_management/po_template/designer",               to: "po_templates#designer",                 as: "designer_vendor_management_po_template"
  patch  "vendor_management/po_template/layout",                 to: "po_templates#update_layout",            as: "update_layout_vendor_management_po_template"
  get    "vendor_management/po_template/preview",                to: "po_templates#preview",                  as: "preview_vendor_management_po_template"

  get    "vendor_management/approval_chain",                    to: "approval_chain_templates#show",         as: "vendor_management_approval_chain"
  get    "vendor_management/approval_chain/steps/new",          to: "approval_chain_templates#new_step",     as: "new_vendor_management_approval_step"
  post   "vendor_management/approval_chain/steps",              to: "approval_chain_templates#create_step",  as: "vendor_management_approval_steps"
  get    "vendor_management/approval_chain/steps/:id/edit",     to: "approval_chain_templates#edit_step",    as: "edit_vendor_management_approval_step"
  patch  "vendor_management/approval_chain/steps/:id",          to: "approval_chain_templates#update_step",  as: "vendor_management_approval_step"
  delete "vendor_management/approval_chain/steps/:id",          to: "approval_chain_templates#destroy_step", as: "vendor_management_approval_step_destroy"

  scope "projects/:project_id", as: "projects" do
    get    "vendor_management/purchase_orders",                       to: "purchase_orders#index",            as: "vendor_management_purchase_orders"
    get    "vendor_management/purchase_orders/new",                   to: "purchase_orders#new",              as: "new_vendor_management_purchase_order"
    post   "vendor_management/purchase_orders",                       to: "purchase_orders#create",            as: "vendor_management_purchase_orders_create"

    post   "vendor_management/purchase_orders/bulk_destroy",          to: "purchase_orders#bulk_destroy",     as: "bulk_destroy_vendor_management_purchase_orders"
    get    "vendor_management/purchase_orders/export",                to: "purchase_orders#export_excel",     as: "export_vendor_management_purchase_orders"
    get    "vendor_management/purchase_orders/import/new",            to: "purchase_orders#import_new",       as: "import_new_vendor_management_purchase_orders"
    post   "vendor_management/purchase_orders/import",                to: "purchase_orders#import_create",    as: "import_vendor_management_purchase_orders"

    get    "vendor_management/purchase_orders/:po_id/edit",           to: "purchase_orders#edit",             as: "edit_vendor_management_purchase_order"
    patch  "vendor_management/purchase_orders/:po_id",                to: "purchase_orders#update",           as: "vendor_management_purchase_order"
    delete "vendor_management/purchase_orders/:po_id",                to: "purchase_orders#destroy",           as: "vendor_management_purchase_order_destroy"

    get    "vendor_management/purchase_orders/:po_id/line_items/new", to: "purchase_orders#new_line_item",    as: "new_vendor_management_po_line_item"
    post   "vendor_management/purchase_orders/:po_id/line_items",     to: "purchase_orders#create_line_item", as: "vendor_management_po_line_items"
    get    "vendor_management/po_line_items/:id/edit",                to: "purchase_orders#edit_line_item",   as: "edit_vendor_management_po_line_item"
    patch  "vendor_management/po_line_items/:id",                     to: "purchase_orders#update_line_item", as: "vendor_management_po_line_item"
    delete "vendor_management/po_line_items/:id",                     to: "purchase_orders#destroy_line_item", as: "vendor_management_po_line_item_destroy"

    get    "vendor_management/purchase_orders/:po_id/line_items/import/sample", to: "purchase_orders#import_line_items_sample", as: "import_sample_vendor_management_po_line_items"
    get    "vendor_management/purchase_orders/:po_id/line_items/import/new",    to: "purchase_orders#import_line_items_new",    as: "import_new_vendor_management_po_line_items"
    post   "vendor_management/purchase_orders/:po_id/line_items/import",        to: "purchase_orders#import_line_items_create", as: "import_vendor_management_po_line_items"

    get    "vendor_management/purchase_orders/:po_id/export",                    to: "purchase_orders#export_pdf",            as: "export_vendor_management_purchase_order"
    patch  "vendor_management/purchase_orders/:po_id/delivery_status",           to: "purchase_orders#update_delivery_status", as: "update_vendor_management_purchase_order_delivery_status"
    post   "vendor_management/purchase_orders/:po_id/mark_all_delivered",        to: "purchase_orders#mark_all_delivered",     as: "mark_all_delivered_vendor_management_purchase_order"

    post   "vendor_management/purchase_orders/:po_id/submit_for_approval", to: "purchase_orders#submit_for_approval", as: "submit_vendor_management_purchase_order_for_approval"
    patch  "vendor_management/po_approval_steps/:id/approve",              to: "purchase_orders#approve_step",        as: "approve_vendor_management_po_approval_step"
    patch  "vendor_management/po_approval_steps/:id/reject",               to: "purchase_orders#reject_step",         as: "reject_vendor_management_po_approval_step"

    post   "vendor_management/purchase_orders/:po_id/payments",       to: "purchase_orders#create_payment",   as: "vendor_management_po_payments"
    get    "vendor_management/po_payments/:id/edit",                  to: "purchase_orders#edit_payment",     as: "edit_vendor_management_po_payment"
    patch  "vendor_management/po_payments/:id",                       to: "purchase_orders#update_payment",   as: "vendor_management_po_payment"
    delete "vendor_management/po_payments/:id",                       to: "purchase_orders#destroy_payment",  as: "vendor_management_po_payment_destroy"

    get    "vendor_management/purchase_orders/:po_id/quotation_file",  to: "purchase_orders#download_quotation_file", as: "vendor_management_purchase_order_quotation_file"
    delete "vendor_management/purchase_orders/:po_id/quotation_file",  to: "purchase_orders#destroy_quotation_file",   as: "destroy_vendor_management_purchase_order_quotation_file"
  end
end


