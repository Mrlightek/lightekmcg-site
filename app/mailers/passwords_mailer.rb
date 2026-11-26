class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @first_use = user.password_setup_required?
    @password_url = if @first_use
      minutes = AccountSetupSetting.link_minutes
      @setup_link_lifetime = AccountSetupSetting::LIFETIMES.fetch(minutes)
      edit_account_setup_url(user.password_setup_token(link_minutes: minutes))
    else
      edit_password_url(user.password_reset_token)
    end
    mail subject: (@first_use ? 'Set up your Lightek account' : 'Reset your password'), to: user.email_address
  end
end
