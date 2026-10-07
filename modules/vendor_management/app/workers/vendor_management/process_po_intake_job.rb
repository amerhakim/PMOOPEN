module VendorManagement
  # Reads one uploaded PO file in the background (OCR + local AI can take a
  # few minutes on this server) and stores the result for the review screen.
  class ProcessPoIntakeJob < ApplicationJob
    queue_with_priority :low

    def perform(import_id)
      import = VendorManagement::PoIntake.find_by(id: import_id)
      return if import.nil? || import.status != "queued"

      import.update_columns(status: "processing", stage: "Starting", updated_at: Time.current)
      result = VendorManagement::PoReader::Pipeline.new(import).call
      import.update!(status: "ready", stage: nil, result: result.to_json, error_message: nil)
    rescue StandardError => e
      import&.update_columns(status: "failed", stage: nil, error_message: e.message.to_s.truncate(500), updated_at: Time.current)
      Rails.logger.error("[PoIntake #{import_id}] #{e.class}: #{e.message}")
    end
  end
end
