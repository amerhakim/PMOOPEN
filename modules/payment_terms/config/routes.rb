Rails.application.routes.draw do
  scope "projects/:project_id", as: "projects" do
    get    "pmo_dashboard",                             to: "pmo_dashboard#show",            as: "pmo_dashboard"

    get    "payment_terms",                             to: "payment_terms#index",          as: "payment_terms"

    get    "payment_terms/lines/new",                   to: "payment_terms#new_line",        as: "new_payment_terms_line"
    post   "payment_terms/lines",                       to: "payment_terms#create_line",     as: "payment_terms_lines"
    get    "payment_terms/lines/:line_id/edit",         to: "payment_terms#edit_line",        as: "edit_payment_terms_line"
    patch  "payment_terms/lines/:line_id",              to: "payment_terms#update_line",      as: "payment_terms_line"
    delete "payment_terms/lines/:line_id",              to: "payment_terms#destroy_line",    as: "destroy_payment_terms_line"

    get    "payment_terms/lines/:line_id/payments/new", to: "payment_terms#new_payment",      as: "new_payment_terms_payment"
    post   "payment_terms/lines/:line_id/payments",     to: "payment_terms#create_payment",   as: "payment_terms_payments"
    get    "payment_terms/payments/:id/edit",           to: "payment_terms#edit_payment",     as: "edit_payment_terms_payment"
    patch  "payment_terms/payments/:id",                to: "payment_terms#update_payment",   as: "payment_terms_payment"
    delete "payment_terms/payments/:id",                to: "payment_terms#destroy_payment", as: "destroy_payment_terms_payment"
  end

  get "my/payment_terms", to: "payment_terms#my_projects", as: "my_payment_terms"
  get "my/pmo_dashboard", to: "pmo_dashboard#my_projects", as: "my_pmo_dashboard"

  # Grid widget endpoint (Turbo Frame source for the Angular widget
  # component) -- path matches PathHelperService#projectWidgetPath exactly,
  # same URL shape as the native modules/grids widgets (project_status,
  # description, ...) without needing to touch modules/grids itself.
  get "projects/:project_id/widgets/pmo_dashboard",
      to: "grids/widgets/pmo_dashboard#show",
      as: "pmo_dashboard_grid_widget"
end
