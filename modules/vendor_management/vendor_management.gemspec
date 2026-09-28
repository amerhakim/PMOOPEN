Gem::Specification.new do |s|
  s.name        = "vendor_management"
  s.version     = "1.0.0"
  s.authors     = ["OpenProject GmbH"]
  s.summary     = "Vendor, purchase order, invoice, and hardware delivery tracking per project."

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"

  # Vendor list export/import (REQ-PO-08's Excel pattern, applied here
  # first for Vendor Master per the user's direct request).
  s.add_dependency "caxlsx", "~> 4.1"
  s.add_dependency "roo", "~> 2.10"

  # Reshapes Arabic text into its correct joined presentation forms
  # (see PurchaseOrderPdf#shape_arabic) -- Prawn has no Arabic script
  # shaping of its own, so raw Arabic characters would render as
  # disconnected isolated letterforms without this.
  s.add_dependency "arabic-letter-connector", "~> 0.1"
end
