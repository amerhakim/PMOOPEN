module VendorManagement
  module Vendors
    # Mirrors Admin::Enumerations::ItemForm -- Primer's Ruby form DSL
    # instead of hand-written form--field ERB divs.
    class VendorForm < ApplicationForm
      delegate :object, to: :@builder

      form do |form|
        form.text_field(
          name: :name,
          label: object.class.human_attribute_name(:name),
          required: true,
          input_width: :medium
        )

        form.text_field(
          name: :cr_number,
          label: I18n.t("vendor_management.vendor_form.cr_number_label"),
          input_width: :medium
        )

        form.check_box_group(label: I18n.t("vendor_management.vendor_form.category_label")) do |group|
          VendorManagement::Vendor::CATEGORIES.each do |category|
            group.check_box(
              name: "category_list[]",
              label: category,
              value: category,
              checked: object.category_list.include?(category)
            )
          end
        end

        form.text_field(
          name: :country,
          label: I18n.t("vendor_management.vendor_form.country_label"),
          input_width: :medium
        )

        form.text_field(
          name: :contact_name,
          label: I18n.t("vendor_management.vendor_form.contact_name_label"),
          input_width: :medium
        )

        form.text_field(
          name: :contact_email,
          label: I18n.t("vendor_management.vendor_form.contact_email_label"),
          input_width: :medium
        )

        form.text_field(
          name: :contact_phone,
          label: I18n.t("vendor_management.vendor_form.contact_phone_label"),
          input_width: :medium
        )

        form.select_list(
          name: :status,
          label: I18n.t("vendor_management.vendor_form.status_label"),
          input_width: :medium
        ) do |list|
          VendorManagement::Vendor::STATUSES.each do |status|
            list.option(label: status, value: status)
          end
        end

        form.submit(
          name: :submit,
          label: I18n.t("vendor_management.vendor_form.submit"),
          scheme: :primary
        )
      end
    end
  end
end
