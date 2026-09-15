class CustomBrandingController < ApplicationController
  layout "admin"
  menu_item :custom_branding

  UNGUARDED_ACTIONS = %i[logo].freeze

  before_action :require_admin, except: UNGUARDED_ACTIONS
  skip_before_action :check_if_login_required, only: UNGUARDED_ACTIONS
  no_authorization_required! *UNGUARDED_ACTIONS

  def show
    @custom_branding = CustomBranding::Setting.current || CustomBranding::Setting.new
  end

  def update
    @custom_branding = CustomBranding::Setting.current || CustomBranding::Setting.new
    if @custom_branding.update(custom_branding_params)
      flash[:notice] = t(:notice_successful_update)
    else
      flash[:error] = @custom_branding.errors.full_messages.join(", ")
    end
    redirect_to custom_branding_path
  end

  def logo
    custom_branding = CustomBranding::Setting.current
    if custom_branding&.logo&.present?
      expires_in 1.year, public: true, must_revalidate: false
      send_file(custom_branding.logo.path, disposition: "inline")
    else
      head :not_found
    end
  end

  private

  def custom_branding_params
    params.expect(custom_branding: [:logo, :remove_logo, *CustomBranding::Setting::COLOR_FIELDS.map(&:to_sym)])
  end
end
