module VendorManagement
  module Vendors
    # Mirrors Admin::Enumerations::IndexComponent (app/components/admin/
    # enumerations/index_component.rb in core) -- the same SubHeader +
    # BorderBoxListComponent + per-row ItemComponent pattern core itself
    # uses for its own simple "manage a short list of named things"
    # admin screens (Work Package Priorities, Document Categories, ...).
    class IndexComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      options :vendors
      options :can_edit
      options :filters
    end
  end
end
