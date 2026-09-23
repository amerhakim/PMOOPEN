class ImpersonationsController < ApplicationController
  before_action :require_login
  before_action :require_admin, only: %i[index create]

  no_authorization_required! :index, :create, :destroy

  layout "global"

  menu_item :impersonation

  def index
    @users = User.active.where.not(id: User.current.id).order(:login)
  end

  def create
    target = User.active.find(params[:user_id])
    session[:impersonator_user_id] = User.current.id
    session[:user_id] = target.id
    redirect_to "/", notice: t("impersonation.notices.started", name: target.name)
  end

  def destroy
    admin_id = session.delete(:impersonator_user_id)
    if admin_id
      session[:user_id] = admin_id
      redirect_to "/", notice: t("impersonation.notices.stopped")
    else
      redirect_to "/"
    end
  end

  private

  # Deliberately NOT before_action'd on `destroy` -- by the time this runs,
  # User.current is whoever was being impersonated (who may not be an
  # admin at all), so the declarative admin check would wrongly block
  # returning to your own account. Anyone can call destroy; it only ever
  # does anything if session[:impersonator_user_id] is actually set.
  def require_admin
    deny_access unless User.current.admin?
  end
end
