class VendorManagementController < ApplicationController
  # No @project here (Vendor Master is company-wide, see the
  # engine) -- the default layout only renders the sidebar when
  # @project is set, exactly the bug PmoDashboardController#my_projects
  # hit earlier in this project (see openproject_dev_workflow memory).
  # layouts/global.html.erb supplies :global_menu instead, matching
  # the :global_menu entry this controller is actually linked from.
  layout "global"

  before_action :require_login
  before_action :find_vendor, only: %i[edit update destroy]
  before_action :require_vendor_management_view

  # See VendorManagement::Engine for why this module has no declarative
  # project permission to hook `authorize` into -- Vendor Master is
  # company-wide data, so authorization here is done by hand (view/edit
  # role checks below), the same way PmoDashboardController#my_projects
  # does its own filtering instead of the declarative per-project check.
  no_authorization_required! :index, :new, :create, :edit, :update, :destroy, :bulk_destroy, :export, :import_new, :import_create

  menu_item :vendor_management

  def index
    @filters = filter_params
    @vendors = filtered_vendors
    @can_edit = vendor_management_editor?
  end

  def bulk_destroy
    return deny_access unless vendor_management_editor?

    ids = Array(params[:vendor_ids]).reject(&:blank?)
    if ids.empty?
      redirect_to vendor_management_vendors_path, alert: t("vendor_management.index.no_vendors_selected")
      return
    end

    count = VendorManagement::Vendor.where(id: ids).destroy_all.size
    redirect_to vendor_management_vendors_path, notice: t("vendor_management.index.vendors_deleted", count:)
  end

  # Kept public (not private) -- VendorManagement::Vendors::IndexComponent
  # and ItemComponent call this via `helpers.` from within the view
  # context, same as core's own ItemComponents do for their controller's
  # own gating methods where needed.
  def can_edit?
    @can_edit
  end
  helper_method :can_edit?

  def new
    return deny_access unless vendor_management_editor?

    @vendor = VendorManagement::Vendor.new
  end

  def create
    return deny_access unless vendor_management_editor?

    @vendor = VendorManagement::Vendor.new(vendor_params)
    if @vendor.save
      redirect_to vendor_management_vendors_path, notice: t("vendor_management.notices.vendor_created")
    else
      render :new
    end
  end

  def edit
    return deny_access unless vendor_management_editor?
  end

  def update
    return deny_access unless vendor_management_editor?

    if @vendor.update(vendor_params)
      redirect_to vendor_management_vendors_path, notice: t("vendor_management.notices.vendor_updated")
    else
      render :edit
    end
  end

  def destroy
    return deny_access unless vendor_management_editor?

    @vendor.destroy
    redirect_to vendor_management_vendors_path, notice: t("vendor_management.notices.vendor_deleted")
  end

  def export
    send_data VendorManagement::VendorExport.new.call,
              filename: "vendors-#{Date.current.iso8601}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_new
    return deny_access unless vendor_management_editor?
  end

  def import_create
    return deny_access unless vendor_management_editor?

    uploaded = params[:file]
    if uploaded.blank?
      redirect_to import_new_vendor_management_vendors_path, alert: t("vendor_management.import.no_file")
      return
    end

    result = VendorManagement::VendorImport.new(uploaded.path).call
    flash[:notice] = t("vendor_management.import.summary",
                        created: result.created.size, updated: result.updated.size)
    flash[:error] = result.errors.join(" | ") if result.errors.any?
    redirect_to vendor_management_vendors_path
  rescue StandardError => e
    redirect_to import_new_vendor_management_vendors_path,
                alert: t("vendor_management.import.parse_error", message: e.message)
  end

  private

  def find_vendor
    @vendor = VendorManagement::Vendor.find(params[:id])
  end

  def filtered_vendors
    scope = VendorManagement::Vendor.includes(:vendor_categories).order(:name)

    scope = scope.where("vendor_management_vendors.name ILIKE ?", "%#{VendorManagement::Vendor.sanitize_sql_like(filter_params[:name])}%") if filter_params[:name].present?
    scope = scope.where("vendor_management_vendors.country ILIKE ?", "%#{VendorManagement::Vendor.sanitize_sql_like(filter_params[:country])}%") if filter_params[:country].present?
    scope = scope.where("vendor_management_vendors.contact_name ILIKE ?", "%#{VendorManagement::Vendor.sanitize_sql_like(filter_params[:contact_name])}%") if filter_params[:contact_name].present?
    scope = scope.where("vendor_management_vendors.contact_email ILIKE ?", "%#{VendorManagement::Vendor.sanitize_sql_like(filter_params[:contact_email])}%") if filter_params[:contact_email].present?
    scope = scope.where("vendor_management_vendors.contact_phone ILIKE ?", "%#{VendorManagement::Vendor.sanitize_sql_like(filter_params[:contact_phone])}%") if filter_params[:contact_phone].present?
    scope = scope.where(status: filter_params[:status]) if filter_params[:status].present?

    if filter_params[:category].present?
      scope = scope.where(id: VendorManagement::VendorCategory.where(category: filter_params[:category]).select(:vendor_id))
    end

    scope
  end

  def filter_params
    params.fetch(:q, {}).permit(:name, :category, :country, :contact_name, :contact_email, :contact_phone, :status)
  end

  def vendor_params
    params.require(:vendor).permit(
      :name, :cr_number, :country, :contact_name, :contact_email, :contact_phone, :status,
      category_list: []
    )
  end

  def require_vendor_management_view
    deny_access unless vendor_management_viewer?
  end

  def vendor_management_viewer?
    User.current.admin? || current_user_has_role?("Procurement Manager", "Finance")
  end

  def vendor_management_editor?
    User.current.admin? || current_user_has_role?("Procurement Manager")
  end

  def current_user_has_role?(*names)
    User.current.memberships.any? { |m| m.roles.exists?(name: names) }
  end
end
