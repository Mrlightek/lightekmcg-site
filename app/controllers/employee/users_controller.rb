# frozen_string_literal: true
module Employee
  # Account/role management is more sensitive than Clients/Projects/Tickets —
  # gated to admin/super_admin only, not plain employee?, and a regular admin
  # can't grant super_admin (only a super_admin can create another one).
  class UsersController < Employee::ApplicationController
    before_action :require_admin!
    before_action :set_user, only: %i[edit update destroy]

    def index
      authorize! :read, User
      @users = User.order(:role, :last_name, :first_name)
    end

    def new
      authorize! :create, User
      @user = User.new(role: "client")
    end

    def create
      authorize! :create, User
      @user = User.new(user_params)
      guard_role_escalation!(@user)
      if @user.save
        redirect_to employee_users_path, notice: "User created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize! :update, @user
    end

    def update
      authorize! :update, @user
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
      @user.assign_attributes(attrs)
      guard_role_escalation!(@user)
      if @user.save
        redirect_to employee_users_path, notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize! :destroy, @user
      if @user == current_user
        redirect_to employee_users_path, alert: "You can't delete your own account."
        return
      end
      @user.destroy
      redirect_to employee_users_path, notice: "User removed."
    end

    private

    def require_admin!
      return if current_user&.admin?
      redirect_to employee_dashboard_path, alert: "Admins only."
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email_address, :first_name, :last_name, :role,
                                    :password, :password_confirmation)
    end

    # Only a super_admin can create/promote another super_admin.
    def guard_role_escalation!(user)
      return unless user.role == "super_admin"
      return if current_user.role == "super_admin"

      user.role = user.role_was.presence || "client"
    end
  end
end
