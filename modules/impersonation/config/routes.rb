Rails.application.routes.draw do
  get    "impersonation",          to: "impersonations#index",   as: "impersonations"
  post   "impersonation/:user_id", to: "impersonations#create",  as: "impersonation_create"
  delete "impersonation",          to: "impersonations#destroy", as: "impersonation"
end
