class MemberEmailsController < ApplicationController
  skip_authorization_check
  layout 'auth'
  protect_from_forgery with: :exception
  before_action { response.set_header('Cache-Control', 'private, no-store'); response.set_header('Referrer-Policy', 'no-referrer') }
  def show
    @token = params[:token].to_s
    @member = User.find_by_token_for(:email_verification, @token)
    return render(plain: 'This confirmation link has expired. Request another from Membership.', status: :unprocessable_entity) unless @member == current_user
  end
  def create
    member = User.find_by_token_for(:email_verification, params[:token].to_s)
    return render(plain: 'This confirmation link has expired or belongs to another account.', status: :unprocessable_entity) unless member == current_user
    LightekEmailProvisioningService.confirm!(current_user)
    redirect_to '/lightek/index.html#/membership', notice: 'Your Lightek mailbox has been created.'
  rescue LightekEmailProvisioningService::Unavailable, ActiveRecord::RecordInvalid
    redirect_to '/lightek/index.html#/membership', alert: 'Your inbox could not be created yet. Your existing account is preserved.'
  end
end
