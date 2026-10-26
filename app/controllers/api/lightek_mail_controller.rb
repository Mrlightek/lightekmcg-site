require "digest"
class Api::LightekMailController < ActionController::API
  before_action :secure_transport
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekMail::Submission::Unavailable, with: :invalid
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  def create
    account = authenticated_account
    return head :unauthorized unless account
    key = request.headers["Idempotency-Key"].to_s
    raise ArgumentError, "Supply an Idempotency-Key for safe request retries." if key.blank?
    message = LightekMail::Submission.create!(account: account, idempotency_key: key,
      attributes: params.permit(:from, :to, :subject, :text, :html, :template_id, to: [], cc: [], bcc: [], attachments: [:filename, :content_type, :data], variables: {}).to_h)
    render json: {id: message.id, status: message.state, status_url: "/api/lightek-mail/messages/#{message.id}"}, status: :accepted
  end
  def show
    account = authenticated_account
    return head :unauthorized unless account
    message = account.messages.find(params[:id])
    render json: {id: message.id, status: message.state, accepted_by_smtp_at: message.submitted_at, error: message.error_message}
  end
  def inbound
    secret = ENV["LIGHTEK_MAIL_INGRESS_TOKEN"].to_s
    return head :service_unavailable if secret.bytesize < 32
    supplied = request.headers["X-Lightek-Mail-Ingress"].to_s
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(secret), Digest::SHA256.hexdigest(supplied))
    recipients = JSON.parse(request.headers["X-Lightek-Mail-Recipients"].to_s)
    raise ArgumentError, "Use an envelope recipient array." unless recipients.is_a?(Array)
    raw = request.body.read(14 * 1024 * 1024 + 1)
    LightekMail::Inbound.accept!(raw: raw, recipients: recipients)
    head :accepted
  rescue JSON::ParserError
    head :unprocessable_entity
  end
  def feedback
    secret = ENV["LIGHTEK_MAIL_FEEDBACK_TOKEN"].to_s
    return head :service_unavailable if secret.bytesize < 32
    supplied = request.headers["X-Lightek-Mail-Feedback"].to_s
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(secret), Digest::SHA256.hexdigest(supplied))
    LightekMail::Feedback.record!(message_id: params.require(:message_id), kind: params.require(:kind), event_key: params.require(:event_key))
    head :accepted
  end
  private
  def secure_transport
    response.set_header("Cache-Control", "private, no-store")
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    head :payload_too_large if request.content_length.to_i > 14 * 1024 * 1024
  end
  def authenticated_account
    token = request.authorization.to_s.match(/\ABearer (lm_[a-f0-9]{64})\z/)&.captures&.first
    account = LightekMail::Account.authenticate(token)
    return unless account && account.sending_ready?
    LightekMail::Access.authorize!(account.user)
    account
  rescue LightekMail::Access::Denied
    nil
  end
  def invalid(_error) = render(json: {error: "The message could not be accepted. Check mailbox readiness, quota, recipients and template fields."}, status: :unprocessable_entity)
  def not_found = head(:not_found)
end
