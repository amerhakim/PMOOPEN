Rails.application.routes.draw do
  resource :custom_branding, only: %i[show update], controller: "custom_branding"
  get "custom_branding/logo", to: "custom_branding#logo", as: "custom_branding_logo"
end
