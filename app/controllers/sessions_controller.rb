class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }
  skip_authorization_check

  layout "auth", only: :new

  def new
    store_return_to
    redirect_to after_authentication_url if authenticated?
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end

  private

  def store_return_to
    candidate = params[:return_to].to_s

    return if candidate.blank?
    return unless candidate.start_with?("/")
    return if candidate.start_with?("//")
    return if candidate.include?("\\")
    return if candidate.match?(/[\r\n]/)

    session[:return_to_after_authenticating] =
      candidate
  end

end