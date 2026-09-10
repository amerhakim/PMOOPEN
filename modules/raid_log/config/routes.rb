Rails.application.routes.draw do
  scope "projects/:project_id", as: "projects" do
    get "raid_log_ai_assist/new", to: "raid_log_assistant#new", as: "new_raid_log_assistant"
    post "raid_log_ai_assist/propose", to: "raid_log_assistant#propose", as: "raid_log_assistant_propose"
    post "raid_log_ai_assist", to: "raid_log_assistant#create", as: "raid_log_assistant"
  end

  get "work_packages/:work_package_id/raid_log_review",
      to: "raid_log_assistant#review_existing",
      as: "raid_log_review_work_package"
  post "work_packages/:work_package_id/raid_log_review",
       to: "raid_log_assistant#apply_review",
       as: "apply_raid_log_review_work_package"
end
