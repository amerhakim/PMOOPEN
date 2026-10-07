class PurchaseOrdersOverviewController < ApplicationController
  # Company-wide "Purchase Orders" page under the new "Vendor and
  # Procurement" global menu entry -- sits alongside the existing global
  # Vendors page. Purchase orders are still genuinely project-owned data
  # (belongs_to :project, unchanged), this controller just gives
  # Procurement a single cross-project place to browse/search everything
  # and create a new PO without first navigating into a specific
  # project. Once a PO exists it redirects straight into the real,
  # fully-featured per-project workspace (line items, approval,
  # payments, PDF, delivery) -- this controller never duplicates that.
  layout "global"

  before_action :require_login

  # No declarative project_module/permission entry for this controller
  # (it isn't project-scoped) -- same reasoning as VendorManagementController.
  # Row-level and create-time visibility is instead enforced by hand below
  # via Project.allowed_to(user, :view_vendor_management/:edit_vendor_management),
  # which reuses the SAME per-project permission grants the real
  # project-scoped Purchase Orders tab already respects.
  no_authorization_required! :index, :new, :create, :ai_new, :ai_create

  menu_item :vendor_management_purchase_orders_home

  def index
    @filters = filter_params
    @purchase_orders = filtered_purchase_orders
    @can_create = editable_projects.exists?
  end

  def new
    @purchase_order = VendorManagement::PurchaseOrder.new
    @vendors = VendorManagement::Vendor.order(:name)
    @projects = editable_projects
  end

  def create
    @vendors = VendorManagement::Vendor.order(:name)
    @projects = editable_projects

    project = @projects.find_by(id: params.dig(:purchase_order, :project_id))

    @purchase_order = VendorManagement::PurchaseOrder.new(purchase_order_params)
    @purchase_order.project = project

    if project.nil?
      @purchase_order.errors.add(:project_id, :blank)
      render :new
      return
    end

    if @purchase_order.save
      redirect_to projects_edit_vendor_management_purchase_order_path(project, @purchase_order),
                  notice: t("vendor_management.notices.po_created")
    else
      render :new
    end
  end

  # "Create by AI" from the company-wide list: pick the project, upload the
  # file; the rest (reading in the background, review, confirm) is the same
  # per-project flow as on a project's own Purchase Orders tab.
  def ai_new
    @projects = editable_projects
  end

  def ai_create
    project = editable_projects.find_by(id: params[:project_id])
    uploaded = params[:file]
    kind = uploaded && VendorManagement::PoIntake.kind_for(uploaded.original_filename)

    if project.nil?
      flash[:error] = t("vendor_management.purchase_orders_overview.ai_pick_project")
      redirect_to new_vendor_management_po_intake_overview_path
    elsif kind.nil?
      redirect_to new_vendor_management_po_intake_overview_path, alert: t("vendor_management.po_ai.unsupported_file")
    elsif uploaded.size > PoIntakesController::MAX_FILE_SIZE
      redirect_to new_vendor_management_po_intake_overview_path, alert: t("vendor_management.po_ai.file_too_big")
    else
      import = VendorManagement::PoIntake.create!(
        project:, user: User.current, source_kind: kind, source_filename: uploaded.original_filename,
        source_content_type: uploaded.content_type, source_data: uploaded.read, stage: "Waiting to start"
      )
      VendorManagement::ProcessPoIntakeJob.perform_later(import.id)
      redirect_to projects_vendor_management_po_intake_path(project, import)
    end
  end

  private

  # Every project where the current user can at least VIEW purchase
  # orders -- what the overview list is allowed to show.
  # Archived projects are included: their purchase orders still exist (and still
  # own their PO numbers), so the list must not hide them. Admins see every
  # archived project; others only those where their role grants the permission.
  def viewable_projects
    user = User.current
    active = Project.allowed_to(user, :view_vendor_management)
    archived = Project.where(active: false)
                      .where(id: EnabledModule.where(name: "vendor_management").select(:project_id))
    unless user.admin?
      roles = Role.joins(:role_permissions).where(role_permissions: { permission: "view_vendor_management" }).select(:id)
      archived = archived.where(id: Member.joins(:member_roles)
                                          .where(user_id: user.id, member_roles: { role_id: roles }).select(:project_id))
    end
    Project.where(id: active.select(:id)).or(Project.where(id: archived.select(:id)))
  end
  helper_method :viewable_projects

  # Every project where the current user can actually CREATE/edit
  # purchase orders -- what the "New PO" project picker offers, and the
  # only projects #create is allowed to write into.
  def editable_projects
    Project.allowed_to(User.current, :edit_vendor_management).order(:name)
  end

  def filtered_purchase_orders
    scope = VendorManagement::PurchaseOrder.where(project: viewable_projects)
            .includes(:vendor, :project).order(:po_number)

    f = filter_params
    scope = scope.where("po_number ILIKE ?", "%#{VendorManagement::PurchaseOrder.sanitize_sql_like(f[:po_number])}%") if f[:po_number].present?
    scope = scope.where(project_id: f[:project_id]) if f[:project_id].present?
    scope = scope.where(vendor_id: f[:vendor_id]) if f[:vendor_id].present?
    scope = scope.where(currency: f[:currency]) if f[:currency].present?
    scope = scope.where(status: f[:status]) if f[:status].present?

    case f[:payment_status]
    when "not_invoiced" then scope = scope.where(total_paid: 0)
    when "paid" then scope = scope.where("remaining_in_po <= 0")
    when "partially_paid" then scope = scope.where("total_paid > 0 AND remaining_in_po > 0")
    end

    scope
  end

  def filter_params
    params.fetch(:q, {}).permit(:po_number, :project_id, :vendor_id, :currency, :status, :payment_status)
  end

  def purchase_order_params
    params.require(:purchase_order).permit(:vendor_id, :po_number, :o_and_d, :issue_date, :currency, :total_value)
  end
end


