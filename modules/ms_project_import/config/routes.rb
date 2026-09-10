Rails.application.routes.draw do
  scope "projects/:project_id", as: "projects" do
    resources :ms_project_imports, only: %i[new create show]
  end
end
