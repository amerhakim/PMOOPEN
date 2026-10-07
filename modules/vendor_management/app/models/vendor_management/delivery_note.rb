module VendorManagement
  # A delivery note (PDF or photo) kept with a project, usually against one of
  # its purchase orders. The file itself lives in the `data` column; lists load
  # rows with `without_data` so they never pull the bytes.
  class DeliveryNote < ApplicationRecord
    self.table_name = "vendor_management_delivery_notes"

    ALLOWED_EXTENSIONS = %w[.pdf .png .jpg .jpeg .gif .webp .tif .tiff].freeze
    MAX_SIZE = 25.megabytes
    SIGNATURES = {
      ".pdf" => ["%PDF"], ".png" => ["\x89PNG".b], ".jpg" => ["\xFF\xD8".b], ".jpeg" => ["\xFF\xD8".b],
      ".gif" => ["GIF8"], ".webp" => ["RIFF"], ".tif" => ["II*\0".b, "MM\0*".b], ".tiff" => ["II*\0".b, "MM\0*".b]
    }.freeze

    belongs_to :project
    belongs_to :purchase_order, class_name: "VendorManagement::PurchaseOrder", optional: true, inverse_of: :delivery_notes
    belongs_to :uploaded_by, class_name: "User"

    validates :filename, presence: true
    validates :byte_size, numericality: { greater_than: 0, less_than_or_equal_to: MAX_SIZE }
    validate :allowed_file
    validate :purchase_order_belongs_to_project

    scope :without_data, -> { select(column_names - ["data"]) }

    def self.from_upload(uploaded, project:, purchase_order:, user:)
      bytes = uploaded.read
      new(project:, purchase_order:, uploaded_by: user, filename: File.basename(uploaded.original_filename.to_s),
          content_type: uploaded.content_type, byte_size: bytes.bytesize, data: bytes)
    end

    def extension
      File.extname(filename.to_s).downcase
    end

    private

    def allowed_file
      return if filename.blank?

      unless ALLOWED_EXTENSIONS.include?(extension)
        errors.add(:filename, :invalid)
        return
      end
      return if data.blank?

      head = data.byteslice(0, 8).to_s.b
      ok = SIGNATURES.fetch(extension, []).any? { |sig| head.start_with?(sig.b) }
      errors.add(:base, "#{filename} does not look like a #{extension.delete('.').upcase} file.") unless ok
    end

    def purchase_order_belongs_to_project
      return if purchase_order.nil? || purchase_order.project_id == project_id

      errors.add(:purchase_order, :invalid)
    end
  end
end
