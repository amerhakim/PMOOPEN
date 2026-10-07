module VendorManagement
  # One uploaded file waiting to become purchase orders. `result` holds the
  # AI's reading (JSON) until the user reviews and confirms it.
  class PoIntake < ApplicationRecord
    self.table_name = "vendor_management_po_intakes"

    STATUSES = %w[queued processing ready failed confirmed].freeze
    SOURCE_KINDS = %w[pdf excel].freeze

    belongs_to :project
    belongs_to :user

    validates :source_kind, inclusion: { in: SOURCE_KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :source_filename, :source_data, presence: true

    def self.kind_for(filename)
      case File.extname(filename.to_s).downcase
      when ".pdf" then "pdf"
      when ".xlsx", ".xlsm", ".csv" then "excel"
      end
    end

    def result_data
      result.present? ? JSON.parse(result) : {}
    end

    def result_data=(hash)
      self.result = hash.to_json
    end

    def working?
      %w[queued processing].include?(status)
    end

    def update_stage!(label)
      update_columns(stage: label, updated_at: Time.current)
    end
  end
end
