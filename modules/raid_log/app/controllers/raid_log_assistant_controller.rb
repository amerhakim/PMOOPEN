class RaidLogAssistantController < ApplicationController
  before_action :find_project, only: %i[new propose create]
  before_action :find_work_package, only: %i[review_existing apply_review]
  before_action :authorize

  menu_item :raid_log_assistant

  def new
    @type_names = RaidLog::LogTypeFields.type_names
  end

  def propose
    @type_name = params[:type_name]
    @user_context = params[:user_context]
    @count = params[:count].presence || 3

    call = RaidLog::SuggestEntriesService.new(
      project: @project, type_name: @type_name, user_context: @user_context, count: @count
    ).call

    if call.success?
      @type = RaidLog::LogTypeFields.find_type!(@type_name)
      @field_spec = RaidLog::LogTypeFields.field_spec_for(@type)
      @suggestions = call.result
    else
      flash[:error] = call.message
      redirect_to projects_new_raid_log_assistant_path(@project, type_name: @type_name)
    end
  end

  def create
    type = RaidLog::LogTypeFields.find_type!(params[:type_name])
    entries = (params[:entries] || {}).to_unsafe_h.values.select { |e| e["include"] == "1" }

    created = 0
    entries.each do |entry|
      call = WorkPackages::CreateService.new(user: current_user).call(
        project: @project,
        type:,
        subject: entry["subject"],
        description: entry["description"],
        custom_field_values: submitted_custom_field_values(entry, type)
      )
      created += 1 if call.success?
    end

    flash[:notice] = t("raid_log.notices.entries_created", count: created)
    redirect_to project_work_packages_path(@project, query_props: { c: %w[id type subject], t: "id:desc",
                                                                      f: [{ n: "type", o: "=", v: [type.id.to_s] }] }.to_json)
  end

  def review_existing
    call = RaidLog::ReviewEntryService.new(work_package: @work_package).call
    if call.success?
      @suggestion = call.result
      @field_spec = RaidLog::LogTypeFields.field_spec_for(@work_package.type)
    else
      flash.now[:error] = call.message
    end
  end

  def apply_review
    type = @work_package.type
    entry = params[:entry].to_unsafe_h

    call = WorkPackages::UpdateService.new(user: current_user, model: @work_package).call(
      subject: entry["subject"].presence || @work_package.subject,
      description: entry["description"].presence,
      custom_field_values: submitted_custom_field_values(entry, type)
    )

    if call.success?
      flash[:notice] = t("raid_log.notices.entry_updated")
    else
      flash[:error] = call.errors.full_messages.join(", ")
    end
    redirect_to work_package_path(@work_package)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  def find_work_package
    @work_package = WorkPackage.find(params[:work_package_id])
    @project = @work_package.project
  end

  def submitted_custom_field_values(entry, type)
    custom_fields = entry["custom_fields"] || {}
    RaidLog::LogTypeFields.field_spec_for(type).each_with_object({}) do |field, values|
      value = custom_fields[field[:id].to_s]
      values[field[:id]] = value if value.present?
    end
  end
end
