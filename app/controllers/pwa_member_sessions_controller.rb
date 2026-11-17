class PwaMemberSessionsController < ApplicationController
  allow_unauthenticated_access only: :create
  rate_limit to: 20, within: 1.minute, only: :create
  skip_authorization_check
  rescue_from LightekReservations::Federation::Client::Unavailable, ActiveRecord::RecordNotFound do
    render plain: 'This sign-in link is unavailable or expired. Return to Lightek Membership and open your publishing space again.', status: :unauthorized
  end
  def create
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    site = LightekPwa::SiteContext.resolve(request.host)
    config = site.manifest.to_h['pwa_member'] or raise ActiveRecord::RecordNotFound
    token = params.require(:ticket).to_s
    raise ActiveRecord::RecordNotFound unless token.match?(/\A[a-f0-9]{64}\z/)
    data = LightekReservations::Federation::Client.new(site).request('pwa/member-session', method: :post, body: {ticket: token})
    raise ActiveRecord::RecordNotFound unless data['backend_key'] == config['key'] && data['hostname'] == request.host
    user = site.tenant
    raise ActiveRecord::RecordNotFound unless user.is_a?(User) && user.email_address == data['email']
    session[:return_to_after_authenticating] = '/lightek/index.html#/create'
    complete_primary_authentication_for(user)
  end
end
