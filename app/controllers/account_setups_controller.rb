class AccountSetupsController < PasswordsController
  private
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
