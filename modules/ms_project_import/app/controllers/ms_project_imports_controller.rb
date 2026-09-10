class MsProjectImportsController < ApplicationController
  before_action :find_project
  before_action :authorize
  before_action :find_import, only: %i[show]

  menu_item :ms_project_import

  def new; end

  def create
    file = params[:file]

    if file.blank?
      flash[:error] = t("ms_project_import.errors.no_file_selected")
      redirect_to(new_projects_ms_project_import_path(@project)) && return
    end

    import = MsProjectImport::Import.new(project: @project, user: current_user,
                                          original_filename: file.original_filename)

    unless import.save
      flash[:error] = import.errors.full_messages.join(", ")
      redirect_to(new_projects_ms_project_import_path(@project)) && return
    end

    attach_call = Attachments::CreateService
      .bypass_allowlist(user: current_user)
      .call(container: import, filename: file.original_filename, file:,
            description: "MS Project import source file")

    if attach_call.success?
      MsProjectImportJob.perform_later(ms_project_import: import, user: current_user)
      redirect_to projects_ms_project_import_path(@project, import)
    else
      import.destroy
      flash[:error] = attach_call.errors.full_messages.join(", ")
      redirect_to new_projects_ms_project_import_path(@project)
    end
  end

  def show; end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def find_import
    @import = MsProjectImport::Import.where(project: @project).find(params[:id])
  end
end
