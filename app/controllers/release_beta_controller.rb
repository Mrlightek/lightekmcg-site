# frozen_string_literal: true

class ReleaseBetaController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check
  protect_from_forgery with: :exception
  # Both cross-host endpoints require a short-lived, purpose-bound HMAC.
  skip_before_action :verify_authenticity_token, only: %i[account revoke]
  before_action :private_response
  rate_limit to: 15, within: 1.minute, only: %i[redeem account revoke]
  rescue_from ReleaseAssurance::Policy::Denied, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique, with: -> { head :forbidden }

  def show
    @assignment = assignment
  end

  def redeem
    token = params.require(:invite)
    raise ReleaseAssurance::Policy::Denied unless token.is_a?(String) && token.match?(/\A[0-9a-f]{64}\z/)
    record = ReleaseAssurance::Assignment.find_by!(invite_digest: Digest::SHA256.hexdigest(token))
    record.with_lock do
      raise ReleaseAssurance::Policy::Denied unless record.active? && record.redeemed_at.nil?
      record.update!(redeemed_at: Time.current)
    end
    session[:release_beta_assignment_id] = record.id
    redirect_to release_beta_path, status: :see_other
  end

  def launch
    @assignment = assignment
    raise ReleaseAssurance::Policy::Denied unless @assignment
    @hostname = ReleaseAssurance::Policy.hostname!(@assignment.environment.hostname)
    @assertion = ReleaseAssurance::BetaAccess.token_for(@assignment, purpose: "account")
  end

  def feedback
    record = assignment || raise(ReleaseAssurance::Policy::Denied)
    raise ReleaseAssurance::Policy::Denied unless params[:redacted] == "1"
    ReleaseAssurance::Feedback.record!(record, result: params[:result].to_s,
      note: params[:note].to_s, screenshot: params[:screenshot])
    redirect_to release_beta_path, notice: "Feedback submitted for review.", status: :see_other
  end

  def account
    return head :conflict if authenticated?
    data = ReleaseAssurance::BetaAccess.verify!(params.require(:assertion), hostname: request.host, purpose: "account")
    user = ReleaseAssurance::BetaAccess.account!(data)
    complete_primary_authentication_for(user)
  end

  def revoke
    data = ReleaseAssurance::BetaAccess.verify!(request.authorization.to_s.delete_prefix("Bearer "),
      hostname: request.host, purpose: "revoke")
    ReleaseAssurance::BetaAccess.account!(data, revoke: true)
    head :no_content
  end

  private

  def assignment
    record = ReleaseAssurance::Assignment.find_by(id: session[:release_beta_assignment_id])
    record if record&.active? && record.redeemed_at?
  end

  def private_response
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
