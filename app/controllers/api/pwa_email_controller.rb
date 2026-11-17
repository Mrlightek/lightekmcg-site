module Api
  class PwaEmailController < ApplicationController
    skip_authorization_check
    protect_from_forgery with: :exception
    rate_limit to: 3, within: 1.hour, only: :create
    rescue_from LightekEmailProvisioningService::Unavailable do |e|
      render json: {error: e.message}, status: :unprocessable_entity
    end
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    def create
      site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: current_user, site: site).authorize!
      LightekEmailProvisioningService.domain!
      response.set_header('Cache-Control', 'private, no-store')
      account = LightekMail::Account.mailboxes.find_by(user: current_user, brand_member: true)
      return render(json: {message: 'Your Lightek inbox already exists.'}) if account
      MemberEmailMailer.confirmation(current_user, request.base_url).deliver_later
      render json: {message: 'Check the email address you used to sign up. Confirm it to create your Lightek inbox.'}
    end
    private
    def require_authentication
      return render json: {error: 'Sign in to create your Lightek inbox'}, status: :unauthorized unless authenticated?
      super
    end
  end
end
