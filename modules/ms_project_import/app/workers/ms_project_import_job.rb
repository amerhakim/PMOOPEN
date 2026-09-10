class MsProjectImportJob < ApplicationJob
  queue_with_priority :above_normal

  def perform(ms_project_import:, user:)
    @ms_project_import = ms_project_import

    User.execute_as(user) do
      attachment = ms_project_import.attachments.first
      raise "No source file attached to this import" unless attachment

      parsed = MsProjectImport::ParseService.new(attachment.diskfile.path).call
      result = MsProjectImport::CreateWorkPackagesService.new(
        project: ms_project_import.project,
        user:,
        parsed:
      ).call

      ms_project_import.update!(
        tasks_created_count: result[:tasks_created],
        relations_created_count: result[:relations_created]
      )

      upsert_status(
        status: :success,
        message: I18n.t("ms_project_import.success", tasks: result[:tasks_created], relations: result[:relations_created])
      )
    end
  rescue StandardError => e
    ms_project_import.update(error_message: e.message)
    upsert_status(status: :failure, message: e.message)
    raise e
  end

  def status_reference
    @ms_project_import
  end

  def updates_own_status?
    true
  end
end
