class AccountSetupsController < PasswordsController
  def update
    super
    queue_installation_mailbox if @user&.saved_change_to_password_setup_required?(from: true, to: false)
  end

  private

  def queue_installation_mailbox
    InstallationMailboxJob.perform_later(@user.id) if LightekTeam::Installation.site
  rescue StandardError => error
    Rails.logger.warn("Installation mailbox setup enqueue failed (#{error.class.name}). Mail Studio can retry it.")
  end
  def user_for_token!
    user = User.find_by_token_for!(:password_setup, params[:token])
    raise ActiveSupport::MessageVerifier::InvalidSignature unless user.password_setup_required?
    user
  end

  def prepare_password_form
    @first_use = true
    @password_form_url = account_setup_path(params[:token])
  end
end
