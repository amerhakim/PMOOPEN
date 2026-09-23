require "roo"

module VendorManagement
  # Single-step import (no separate preview/confirm round trip -- if a row
  # is wrong, the report below says exactly why, and re-uploading a fixed
  # file is trivial). Matches an existing vendor by exact name
  # (case-insensitive) and updates it; otherwise creates a new one --
  # this is what makes "export, edit in Excel, re-import" behave like
  # inline list editing, per the user's own request.
  class VendorImport
    Result = Struct.new(:created, :updated, :errors, keyword_init: true)

    def initialize(file_path)
      @file_path = file_path
    end

    def call
      sheet = Roo::Spreadsheet.open(@file_path).sheet(0)
      created = []
      updated = []
      errors = []

      # Row 1 is the header (see VendorExport::COLUMNS) -- data starts row 2.
      (2..sheet.last_row).each do |row_number|
        row = sheet.row(row_number)
        next if row.compact.empty?

        name, cr_number, category_string, country, contact_name, contact_email, contact_phone, status = row

        if name.blank?
          errors << "Row #{row_number}: missing Name, skipped."
          next
        end

        vendor = VendorManagement::Vendor.where("LOWER(name) = ?", name.to_s.strip.downcase).first ||
                 VendorManagement::Vendor.new(name: name.to_s.strip)
        was_new_record = vendor.new_record?

        vendor.cr_number = cr_number
        vendor.country = country
        vendor.contact_name = contact_name
        vendor.contact_email = contact_email
        vendor.contact_phone = contact_phone
        vendor.status = status.presence || "active"
        vendor.category_list = category_string.to_s.split(",").map(&:strip).reject(&:blank?)

        if vendor.save
          was_new_record ? created << vendor.name : updated << vendor.name
        else
          errors << "Row #{row_number} (#{name}): #{vendor.errors.full_messages.join(', ')}"
        end
      end

      Result.new(created:, updated:, errors:)
    end
  end
end
