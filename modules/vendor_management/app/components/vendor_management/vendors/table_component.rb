module VendorManagement
  module Vendors
    # Mirrors core's own Statuses::TableComponent / Users::TableComponent --
    # a real sortable <table> (not the card-list BorderBoxListComponent
    # used before) built on the shared ::TableComponent/::RowComponent
    # base classes core uses for its own admin lists.
    class TableComponent < ::TableComponent
      columns :name, :category, :country, :contact_name, :contact_email, :contact_phone, :status
      sortable_columns :name, :country, :contact_name, :contact_email, :contact_phone, :status

      options :can_edit

      def initial_sort
        %i[name asc]
      end

      def headers
        columns.map { |column| [column.to_s, { caption: I18n.t("vendor_management.columns.#{column}") }] }
      end

      def empty_row_message
        I18n.t("vendor_management.index.no_vendors")
      end
    end
  end
end
