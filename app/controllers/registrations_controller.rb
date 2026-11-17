# frozen_string_literal: true
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  skip_authorization_check
  layout "auth"
  protect_from_forgery with: :exception
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to sign_up_path, alert: "Please try again in a few minutes." }
  before_action :private_registration_page
  before_action :pwa_return_destination
  def new
    @user = User.new
  end
  def create
    @user = User.new(params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation).merge(role: "client"))
    signup_site = LightekPwa::SiteContext.resolve(request.host) if session[:return_to_after_authenticating].to_s.start_with?('/lightek/')
    platform_signup = LightekPwa::Policy.platform_operator(signup_site).present?
    saved = User.transaction do
      if @user.save
        LightekPwa::MemberSignupRequest.find_or_create_by!(site: signup_site, user: @user) if platform_signup
        true
      else
        false
      end
    end
    if saved
      begin
        LightekPwa::MemberSignupJob.perform_later(signup_site.id, @user.id) if platform_signup
      rescue StandardError => error
        Rails.logger.warn("[PWA] Member setup enqueue deferred: #{error.class}")
      end
      flash[:notice] = "Your free account is ready."
      complete_primary_authentication_for(@user)
    else
      render :new, status: :unprocessable_entity
    end
  end
  private
  def pwa_return_destination
    target = params[:return_to].to_s
    if target.start_with?('/lightek/index.html#/') && !target.match?(/[\r\n\\]/)
      session[:return_to_after_authenticating] = target
    end
  end
  def private_registration_page
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
