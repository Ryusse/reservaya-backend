class DashboardController < ApplicationController
  before_action :require_login

  def show
    if current_user.admin?
      render :index_admin, status: :ok
    else
      render :index_user, status: :ok
    end
  end
end