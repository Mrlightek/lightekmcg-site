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
    @folder = params[:folder].to_s.in?(%w[inbox sent draft outbox all trash]) ? params[:folder] : "inbox"
    return unless @account
    @templates = @account.templates.order(:name)
    @messages = @account.messages.where(trashed: @folder == "trash")
    @messages = @messages.where(direction: "inbound", archived: false) if @folder == "inbox"
    @messages = @messages.where(state: @folder) if %w[sent draft].include?(@folder)
    @messages = @messages.where(state: %w[queued submitting failed uncertain]) if @folder == "outbox"
    term = params[:q].to_s.slice(0, 120)
    if term.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      @messages = @messages.where("LOWER(subject) LIKE ? OR LOWER(from_address) LIKE ? OR LOWER(text_body) LIKE ?", *[pattern.downcase] * 3)
    end
    @messages = @messages.order(created_at: :desc).limit(100)
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
    @templates = @account.templates.order(:name)
    @reply = @account.messages.find(params[:reply_id]) if params[:reply_id].present?
    @draft = @account.messages.where(state: "draft").find(params[:draft_id]) if params[:draft_id].present?
  end
  def create_message
    message = LightekMail::Submission.create!(account: @account, attributes: params.permit(:to, :from, :subject, :text, :html, :template_id, :in_reply_to, variables: {}).to_h, draft: params[:commit_action] == "draft", uploads: params[:attachments])
    redirect_to dashboard_mail_message_path(id: message.id, account_id: @account.id)
  end
  def show_message
    @message = @account.messages.find(params[:id])
    @message.update!(read_at: Time.current) if @message.direction == "inbound" && !@message.read_at
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
    redirect_to dashboard_mail_path(account_id: @account.id)
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
  def template_document
    data = params[:document]
    raise ArgumentError, "Supply an email template document." unless data.is_a?(ActionController::Parameters)
    data.permit(*%w[heading body color button_label button_url footer html text]).to_h
  end
  def set_account = @account = LightekMail::Access.accounts(current_user).find(params[:account_id])
  def denied(error) = render(plain: error.message, status: :forbidden)
  def invalid(error)
    text = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(", ") : error.message
    text = "This template changed in another tab. Reload before saving." if error.is_a?(ActiveRecord::StaleObjectError)
    if request.format.json?
      render json: {error: text}, status: :unprocessable_entity
    else
      redirect_to dashboard_mail_path(account_id: @account&.id), alert: text, status: :see_other
    end
  end
end
