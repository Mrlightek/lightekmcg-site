class PasswordsController < ApplicationController
  layout "auth"
  protect_from_forgery with: :exception
  before_action :private_password_page
  rate_limit to: 5, within: 3.minutes, only: :create

  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
    prepare_password_form
    render 'passwords/edit'
  end

  def update
    saved = false
    @user.with_lock do
      # Recheck under the user lock: an already-consumed token cannot win a race.
      user_for_token!
      values = params.permit(:password, :password_confirmation).to_h
      if values['password'].blank? || values['password'].bytesize < 8 || values['password_confirmation'].blank?
        @user.errors.add(:password, 'must have at least 8 characters and a matching confirmation')
      else
        saved = @user.update(values.merge('password_setup_required' => false))
        @user.sessions.delete_all if saved
      end
    end
    if saved
      cookies.delete(:session_id)
      Current.session = nil
      reset_session
      redirect_to new_session_path, notice: "Password saved. Sign in, then complete authenticator setup if your account requires it."
    else
      prepare_password_form
      render 'passwords/edit', status: :unprocessable_entity
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "Password setup link is invalid or has expired. Request a fresh link."
  end

  private
    def private_password_page
      response.headers["Cache-Control"] = "no-store, private"
      response.headers["Referrer-Policy"] = "same-origin"
    end

    def set_user_by_token
      @user = user_for_token!
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end

    def user_for_token! = User.find_by_password_reset_token!(params[:token])
    def prepare_password_form
      @first_use = @user.password_setup_required?
    end
end
