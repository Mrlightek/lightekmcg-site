# frozen_string_literal: true
class Dashboard::MailTransportController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role == "super_admin" }
  before_action :load_status

  def show; end

  def test_delivery
    raise ArgumentError, "Select Lightek SMTP delivery before running this check." unless lightek_smtp?
    if session[:transactional_mail_probe].to_h["sent_at"].to_i > 1.minute.ago.to_i
      return redirect_to dashboard_mail_transport_path, alert: "Wait a minute before sending another delivery check."
    end
    reference = SecureRandom.hex(6)
    # Use the real configured ActionMailer adapter, sender and envelope.
    LightekMail::TransactionalProbeMailer.delivery_probe(current_user.email_address, reference).deliver_now
    session[:transactional_mail_probe] = {"reference" => reference, "recipient" => current_user.email_address,
      "sent_at" => Time.current.to_i, "route" => route_fingerprint}
    redirect_to dashboard_mail_transport_path, notice: "The SMTP server accepted the check. Confirm it arrived in your inbox before retiring Gmail."
  rescue StandardError => error
    # Failed SMTP submission is never receipt evidence, including after an older test.
    session.delete(:transactional_mail_probe)
    Rails.logger.warn "[LightekMail] transactional delivery check failed: #{error.class}"
    redirect_to dashboard_mail_transport_path, alert: "Delivery check failed. Verify Lightek Mail transport and server availability; Gmail remains unchanged."
  end

  def retire_gmail
    proof = session[:transactional_mail_probe].to_h
    valid = lightek_smtp? && proof["sent_at"].to_i.between?(24.hours.ago.to_i, Time.current.to_i) &&
      proof["recipient"] == current_user.email_address && proof["route"] == route_fingerprint &&
      proof["reference"].present? && params[:received] == "1"
    return redirect_to dashboard_mail_transport_path, alert: "Send a fresh Lightek delivery check, then confirm receipt." unless valid
    secret = LightekVault::Secret.find_by(slug: legacy_slug)
    LightekVault::Service.disable!(slug: legacy_slug, requested_by: current_user.email_address) if secret && !secret.disabled?
    session.delete(:transactional_mail_probe)
    redirect_to dashboard_mail_transport_path, notice: "Legacy Gmail credential retired. Transactional mail uses Lightek SMTP."
  end

  private
  def legacy_slug = ENV.fetch("GMAIL_API_VAULT_SLUG", "gmail-api-production")
  def lightek_smtp? = ActionMailer::Base.delivery_method.to_s == "lightek_smtp" && ActionMailer::Base.perform_deliveries
  def route_fingerprint
    settings = LightekMail::Transport.settings
    Digest::SHA256.hexdigest([ActionMailer::Base.delivery_method, settings[:address], settings[:port], settings[:domain], settings[:user_name], ENV.fetch("MAIL_FROM", "no-reply@lightekmcg.com")].to_json)
  end
  def load_status
    @delivery_method = ActionMailer::Base.delivery_method.to_s
    @transport = LightekMail::Transport.settings.slice(:address, :port)
    @lightek_smtp = lightek_smtp?
    @gmail_secret = LightekVault::Secret.find_by(slug: legacy_slug)
    @probe = session[:transactional_mail_probe].to_h
  end
end
