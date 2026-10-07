module VendorManagement
  module Patches
    # When a project's "O&D" custom field value is set/changed (already
    # existing on this instance as a real ProjectCustomField, resolved
    # by NAME here rather than a hardcoded id -- ids differ per
    # environment, see openproject_dev_workflow memory), reassign every
    # VendorManagement::PurchaseOrder whose own o_and_d value matches
    # into that project. Lets procurement raise a PO against an O&D
    # reference before the real project exists yet, then have it land
    # in the right place automatically once the project is created and
    # tagged with the same O&D.
    module CustomValuePatch
      extend ActiveSupport::Concern

      included do
        after_save :attach_matching_purchase_orders, if: :project_o_and_d_value?
      end

      private

      def project_o_and_d_value?
        customized_type == "Project" && value.present? && custom_field&.name == "O&D"
      end

      def attach_matching_purchase_orders
        VendorManagement::PurchaseOrder
          .where(o_and_d: value)
          .where.not(project_id: customized_id)
          .update_all(project_id: customized_id)
      end
    end
  end
end

CustomValue.include VendorManagement::Patches::CustomValuePatch
