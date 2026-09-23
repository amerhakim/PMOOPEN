module VendorManagement
  module PurchaseOrders
    class IndexComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      options :purchase_orders
      options :can_edit
      options :filters
      options :project
    end
  end
end
