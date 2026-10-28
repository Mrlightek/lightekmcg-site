# frozen_string_literal: true
class MarketingSubscriptionsController < ApplicationController
  allow_unauthenticated_access only: %i[create confirm unsubscribe]
  skip_authorization_check
  def create
    site = DymondSite::Site.find(params.require(:site_id))
    email = params.require(:email).to_s.strip.downcase
    contact = LightekMarketing::Contact.find_or_create_by!(site: site, email: email)
    token = contact.signed_id(purpose: :marketing_opt_in, expires_in: 2.days)
    LightekMarketing::SubscriptionMailer.confirm(contact.id, token).deliver_later
    redirect_to commerce_shop_path(site_id: site.id), notice: "Check your email to confirm subscription."
  end
  def confirm
    contact = LightekMarketing::Contact.find_signed!(params.require(:token), purpose: :marketing_opt_in)
    contact.update!(subscribed_at: Time.current, unsubscribed_at: nil, consent_source: "email_double_opt_in")
    render plain: "Subscription confirmed."
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    head :bad_request
  end
  def unsubscribe
    contact = LightekMarketing::Contact.find_signed!(params.require(:token), purpose: :marketing_unsubscribe)
    contact.update!(unsubscribed_at: Time.current)
    render plain: "You have been unsubscribed."
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    head :bad_request
  end
end
