# frozen_string_literal: true
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  skip_authorization_check
  layout "auth"
  protect_from_forgery with: :exception
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to sign_up_path, alert: "Please try again in a few minutes." }
  before_action :private_registration_page
  def new
    @user = User.new
  end
  def create
    @user = User.new(params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation).merge(role: "client"))
    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Your account is ready.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
  private
  def private_registration_page
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
