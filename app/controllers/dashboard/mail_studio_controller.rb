require "zlib"
require "base64"

class Dashboard::MailStudioController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :mail_access
  before_action :set_account, except: %i[index create_domain verify_domain create_account]
  rescue_from LightekMail::Access::Denied, with: :denied
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekMail::Submission::Unavailable, ActiveRecord::StaleObjectError, with: :invalid

  def index
    @accounts = LightekMail::Access.accounts(current_user).includes(:domain).order(:address)
    @domains = LightekMail::Access.domains(current_user).order(:name)
    @account = params[:account_id].present? ? @accounts.find(params[:account_id]) : @accounts.first
    @folder = params[:folder].to_s.in?(%w[inbox unread starred sent draft outbox archived all trash]) ? params[:folder] : "inbox"
    return unless @account
    visible = @account.messages.where(trashed: false)
    @folder_counts = {
      "inbox" => visible.where(direction: "inbound", archived: false).count,
      "unread" => visible.where(direction: "inbound", archived: false, read_at: nil).count,
      "starred" => visible.where(starred: true).count,
      "archived" => visible.where(archived: true).count,
      "sent" => visible.where(state: "sent").count,
      "draft" => visible.where(state: "draft").count,
      "outbox" => visible.where(state: %w[queued submitting failed uncertain]).count,
      "all" => visible.count,
      "trash" => @account.messages.where(trashed: true).count
    }
    @unread_count = visible.where(direction: "inbound", archived: false, read_at: nil).count
    @storage_used = @account.messages.sum(:bytesize)
    @last_received_at = @account.messages.where(direction: "inbound").maximum(:created_at)
    @templates = @account.templates.order(:name)
    @messages = @account.messages.where(trashed: @folder == "trash")
    @messages = @messages.where(direction: "inbound", archived: false) if @folder == "inbox"
    @messages = @messages.where(direction: "inbound", archived: false, read_at: nil) if @folder == "unread"
    @messages = @messages.where(starred: true) if @folder == "starred"
    @messages = @messages.where(archived: true) if @folder == "archived"
    @messages = @messages.where(state: @folder) if %w[sent draft].include?(@folder)
    @messages = @messages.where(state: %w[queued submitting failed uncertain]) if @folder == "outbox"
    @messages = LightekMail::Search.apply(@messages, params[:q])
    @result_count = @messages.count
    @page = params[:page].to_i.clamp(1, [(@result_count / 40.0).ceil, 1].max)
    @messages = @messages.order(created_at: :desc, id: :desc).offset((@page - 1) * 40).limit(40).with_attached_attachments
    @settings = params[:view] == "settings"

  end

  def check_receiving
    result = LightekMail::ReceivingStatus.check(@account)
    flash[result.fetch(:ok) ? :notice : :alert] = result.fetch(:message)
    redirect_to dashboard_mail_path(account_id: @account.id)
  end

  def create_domain
    LightekMail::Domain.create!(user: current_user, name: params[:name])
    redirect_to dashboard_mail_path, notice: "Domain added. Publish its ownership TXT record, then verify."
  end

  def verify_domain
    domain = LightekMail::Access.domains(current_user).find(params[:id])
    LightekMail::DomainVerifier.verify!(domain)
    redirect_to dashboard_mail_path, notice: "Domain ownership verified. Mail routing and sending must also be configured on the server."
  end

  def create_account
    domain = LightekMail::Access.domains(current_user).find(params[:domain_id])
    account = LightekMail::Account.create!(user_id: domain.user_id, domain: domain, address: "#{params[:local_part]}@#{domain.name}", display_name: params[:display_name])
    account.templates.create!(name: "Thank you / acknowledgment", subject: "We received your message", document: {heading: "Thanks for reaching out.", body: "Hi {{name}},\n\nWe received your message about {{subject}}. Our team will get back to you shortly.", footer: account.display_name})
    account.templates.create!(name: "Away / vacation", subject: "Thanks — I’m currently away", document: {heading: "I’m away from my inbox.", body: "Hi {{name}},\n\nThank you for your message. I’ll respond when I return. For urgent requests, please use our usual support channel.", footer: account.display_name})
    redirect_to dashboard_mail_path(account_id: account.id), notice: "Mailbox created, sending paused until the mail administrator enables it."
  end

  def configure_account
    attributes = {auto_reply_enabled: params[:auto_reply_enabled] == "1", auto_template_id: params[:auto_template_id].presence}
    if current_user.role == "super_admin"
      attributes.merge!(enabled: params[:enabled] == "1", daily_limit: params[:daily_limit], storage_limit: params[:storage_limit])
      attributes.merge!(params.permit(:minute_limit, :hour_limit).to_h)
    end
    @account.update!(attributes)
    redirect_to dashboard_mail_path(account_id: @account.id), notice: "Mailbox settings saved."
  end

  def token
    @token = @account.rotate_token!
    render :token
  end

  def compose
    @idempotency_key = "web_#{SecureRandom.hex(24)}"
    @templates = @account.templates.order(:name)
    @draft = @account.messages.where(state: "draft").find(params[:draft_id]) if params[:draft_id].present?
    prepare_reply
    @reply ||= LightekMail::Conversation.parent(@account, @draft) if @draft
    @reply_content = LightekMail::MessageContent.new(@reply) if @reply
    @include_original = @reply.present? && @draft.nil?
    @initial_html = @draft&.html_body
    render layout: false if params[:workspace] == "1"
  end

  def create_message
    prepare_reply
    supplied = params.permit(:to, :cc, :bcc, :from, :subject, :text, :html, :template_id, :in_reply_to, variables: {}).to_h
    supplied["html"] = "" unless params[:rich_text_enabled] == "1"
    attributes = LightekMail::ComposeMessage.attributes(account: @account,
      attributes: supplied,
      original: @reply, mode: @compose_mode, include_original: params[:include_original] == "1")
    message = LightekMail::Submission.create!(account: @account, idempotency_key: params[:idempotency_key].presence || "web_#{SecureRandom.hex(24)}", attributes: attributes, draft: params[:commit_action] == "draft",
      uploads: LightekMail::ComposeMessage.uploads(account: @account, original: @reply, mode: @compose_mode,
        include_attachments: params[:include_attachments] == "1", uploads: params[:attachments]))
    redirect_to dashboard_mail_message_path(id: message.id, account_id: @account.id, workspace: params[:workspace].presence, composed: params[:workspace] == "1" ? params[:commit_action] : nil)
  end

  def show_message
    @message = @account.messages.find(params[:id])
    @conversation = LightekMail::Conversation.messages(@account, @message)
    @content = LightekMail::MessageContent.new(@message)
    @images_enabled = params[:images] == "1"
    @message.update!(read_at: Time.current) if @message.direction == "inbound" && !@message.read_at
    render layout: false if params[:workspace] == "1"
  end

  def send_draft
    message = @account.messages.find(params[:id])
    LightekMail::Submission.send_draft!(@account, message)
    redirect_to dashboard_mail_message_path(id: message.id, account_id: @account.id)
  end

  def flag_message
    message = @account.messages.find(params[:id])
    raise ArgumentError, "Choose archive, trash, star or unread." unless params[:flag].to_s.in?(%w[archived trashed starred unread])
    attrs = params[:flag] == "unread" ? {read_at: nil} : {params[:flag] => params[:value] == "1"}
    message.update!(attrs)
    if params[:return_to] == "message" && params[:flag] == "starred"
      redirect_to dashboard_mail_message_path(account_id: @account.id, id: message.id, workspace: params[:workspace].presence)
    else
      redirect_to dashboard_mail_path(account_id: @account.id)
    end
  end

  def bulk_messages
    ids = Array(params[:message_ids]).map(&:to_s).reject(&:blank?).uniq
    raise ArgumentError, "Select between 1 and 100 messages." unless ids.size.between?(1, 100)
    changes = {"archive" => {archived: true}, "inbox" => {archived: false, trashed: false}, "trash" => {trashed: true},
      "read" => {read_at: Time.current}, "unread" => {read_at: nil}, "star" => {starred: true}, "unstar" => {starred: false}}.fetch(params[:operation].to_s) { raise ArgumentError, "Choose a message action." }
    previous = []
    @account.with_lock do
      records = @account.messages.where(id: ids).lock.to_a
      raise ActiveRecord::RecordNotFound unless records.size == ids.size
      records.each do |record|
        previous << {id: record.id, before: record.attributes.slice(*changes.keys.map(&:to_s))}
        record.update!(changes)
      end
    end
    payload = Base64.strict_encode64(Zlib::Deflate.deflate({account: @account.id, changes: changes, records: previous}.to_json))
    token = Rails.application.message_verifier("mail-undo").generate(payload, expires_in: 10.minutes)
    flash[:mail_undo] = token
    redirect_to dashboard_mail_path(account_id: @account.id, folder: params[:folder], q: params[:q]), notice: "Updated #{ids.size} #{ids.size == 1 ? 'message' : 'messages'}."
  end

  def undo_messages
    payload = Rails.application.message_verifier("mail-undo").verified(params[:undo_token].to_s)
    payload = JSON.parse(Zlib::Inflate.inflate(Base64.strict_decode64(payload))).deep_symbolize_keys if payload
    raise ArgumentError, "This undo has expired. Your messages are unchanged." unless payload && payload[:account] == @account.id
    @account.with_lock do
      payload[:records].each do |entry|
        record = @account.messages.find(entry[:id])
        expected = payload[:changes].stringify_keys
        # Do not overwrite a later action taken in another tab.
        raise ArgumentError, "A message changed since that action. Undo was not applied." unless expected.all? { |key, value| record.public_send(key).to_s == record.class.type_for_attribute(key).cast(value).to_s }
      end
      payload[:records].each { |entry| @account.messages.find(entry[:id]).update!(entry[:before]) }
    end
    redirect_to dashboard_mail_path(account_id: @account.id, folder: params[:folder], q: params[:q]), notice: "Action undone."
  end

  def purge_message
    message = @account.messages.find(params[:id])
    @account.with_lock do
      message.reload
      raise ArgumentError, "Move a completed message or draft to Trash before deleting it." unless message.trashed? && !message.state.in?(%w[queued submitting])
      message.destroy!
    end
    redirect_to dashboard_mail_path(account_id: @account.id, folder: "trash"), notice: "Message permanently deleted."
  end

  def attachment
    message = @account.messages.find(params[:id])
    file = params[:attachment_id] == "source" ? message.source : message.attachments.find(params[:attachment_id])
    raise ActiveRecord::RecordNotFound unless file.respond_to?(:attached?) ? file.attached? : file.present?
    if params[:preview] == "1" && %w[image/png image/jpeg image/gif image/webp application/pdf text/plain].include?(file.content_type)
      response.set_header("Content-Security-Policy", "sandbox; default-src 'none'; style-src 'unsafe-inline'")
      response.set_header("X-Content-Type-Options", "nosniff")
      return send_data file.download, type: file.content_type, disposition: "inline", filename: file.filename.to_s
    end
    send_data file.download, type: "application/octet-stream", disposition: "attachment", filename: params[:attachment_id] == "source" ? "message.eml" : file.filename.to_s
  end

  def edit_template
    @template = params[:id] ? @account.templates.find(params[:id]) : @account.templates.new(name: "New email template", subject: "Hello {{name}}", document: {"heading" => "A message from our team", "body" => "Hi {{name}},\n\nWrite your message here.", "color" => "#284f40"})
  end

  def export_template
    template = @account.templates.find(params[:id])
    content = LightekMail::TemplateRenderer.render(template.document, LightekMail::TemplateRenderer::VARIABLES.to_h { |key| [key, "{{#{key}}}"] })
    part = params[:part] == "text" ? :text : :html
    send_data content.fetch(part), type: "application/octet-stream", disposition: "attachment", filename: "lightek-email-#{template.id}.#{part == :text ? 'txt' : 'html'}"
  end

  def save_template
    template = params[:id] ? @account.templates.find(params[:id]) : @account.templates.new
    template.assign_attributes(name: params[:name], subject: params[:subject], document: template_document)
    template.lock_version = params[:lock_version].to_i if template.persisted?
    template.save!
    redirect_to dashboard_mail_path(account_id: @account.id), notice: "Email template saved."
  end

  def preview_template
    document = template_document
    render json: LightekMail::TemplateRenderer.render(document, {"name" => "Tiff", "email" => "preview@example.test", "company" => @account.display_name, "subject" => "Your recent message"})
  end

  private

  def mail_access
    response.set_header("Cache-Control", "private, no-store")
    LightekMail::Access.authorize!(current_user)
  end

  def prepare_reply
    @compose_mode = params[:mode].to_s.in?(LightekMail::ComposeMessage::MODES) ? params[:mode].to_s : "reply"
    @reply = @account.messages.find(params[:reply_id]) if params[:reply_id].present?
    @reply_recipients = LightekMail::ComposeMessage.recipients(@account, @reply, @compose_mode) if @reply
  end

  def template_document
    data = params[:document]
    raise ArgumentError, "Supply an email template document." unless data.is_a?(ActionController::Parameters)
    data.permit(*%w[heading body color button_label button_url footer html text]).to_h
  end

  def set_account
    acc_id = params[:account_id].presence || params[:id]
    @account = LightekMail::Access.accounts(current_user).find(acc_id)
  end

  def denied(error) = render(plain: error.message, status: :forbidden)

  def invalid(error)
    text = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(", ") : error.message
    text = "This template changed in another tab. Reload before saving." if error.is_a?(ActiveRecord::StaleObjectError)
    if action_name == "create_message" && @account && !request.format.json?
      @templates = @account.templates.order(:name)
      @idempotency_key = params[:idempotency_key].presence || "web_#{SecureRandom.hex(24)}"
      prepare_reply
      @reply_content = LightekMail::MessageContent.new(@reply) if @reply
      @include_original = params[:include_original] == "1"
      @initial_html = LightekMail::TemplateRenderer.clean_html(params[:html]) if params[:rich_text_enabled] == "1"
      @draft = @account.messages.new(subject: params[:subject], text_body: params[:text], in_reply_to: params[:in_reply_to],
        to_addresses: params[:to].to_s.split(",").map(&:strip), cc_addresses: params[:cc].to_s.split(",").map(&:strip), bcc_addresses: params[:bcc].to_s.split(",").map(&:strip))
      @compose_error = "#{text} Your message is preserved below. Select attachments again before retrying."
      flash.now[:alert] = @compose_error
      render :compose, status: :unprocessable_entity, layout: params[:workspace] == "1" ? false : nil
    elsif request.format.json?
      render json: {error: text}, status: :unprocessable_entity
    else
      redirect_to dashboard_mail_path(account_id: @account&.id), alert: text, status: :see_other
    end
  end
end
