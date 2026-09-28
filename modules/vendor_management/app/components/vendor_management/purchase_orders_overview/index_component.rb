module VendorManagement
  module PurchaseOrdersOverview
    class IndexComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      options :purchase_orders
      options :filters
      options :can_create
    end
  end
end
