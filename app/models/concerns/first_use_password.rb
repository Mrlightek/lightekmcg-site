module FirstUsePassword
  extend ActiveSupport::Concern
  included do
    attr_accessor :skip_password_setup_invitation
    attr_reader :password_setup_invitation_error
    generates_token_for :password_setup, expires_in: 20.minutes do
      [password_salt.last(10), password_setup_required?]
    end
    after_create_commit :invite_first_use_account
  end

  def send_password_setup_invitation!
    raise ArgumentError, 'This account already has a chosen password' unless password_setup_required?
    PasswordsMailer.reset(self).deliver_later
  end

  private
  def invite_first_use_account
    # Deployed owners get the verified installation handoff from the control
    # plane, after installation. Do not send an invitation during remote bootstrap.
    return unless password_setup_required? && !skip_password_setup_invitation
    send_password_setup_invitation!
  rescue StandardError => error
    @password_setup_invitation_error = true
    Rails.logger.error("[Account setup] invitation enqueue failed user=#{id} #{error.class}")
  end
end
