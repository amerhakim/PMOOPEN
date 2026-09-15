module MsProjectImport
  class Import < ApplicationRecord
    self.table_name = "ms_project_imports"

    belongs_to :project
    belongs_to :user

    has_one :job_status,
            -> { where(reference_type: "MsProjectImport::Import") },
            class_name: "JobStatus::Status",
            foreign_key: :reference_id

    acts_as_attachable view_permission: :import_ms_project,
                        add_permission: :import_ms_project,
                        delete_permission: :import_ms_project,
                        only_user_allowed: true

    validates :original_filename, presence: true
  end
end
