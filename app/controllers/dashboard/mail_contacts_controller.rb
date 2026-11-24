class Dashboard::MailContactsController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_account
  before_action :load_contact, only: %i[edit update]

  rescue_from LightekMail::Access::Denied do
    head :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
  rescue_from ArgumentError do |error|
    redirect_to contacts_path, alert: error.message, status: :see_other
  end

  def index
    @team_mailbox = team_mailbox(params[:team_mailbox_id])
    scope = LightekMail::Contact.for_mailbox(@account)
    @query = params[:q].to_s.strip.slice(0, 100)
    scope = scope.search(@query) if @query.present?
    @page = params[:page].to_i.clamp(1, 10_000)
    @contacts = scope.order(:name, :id).offset((@page - 1) * 50).limit(51).to_a
  end

  def preview
    row = team_mailbox(params[:team_mailbox_id])
    preview = LightekMail::ContactImport.preview!(account: @account, upload: params[:contacts_csv], team_mailbox: row)
    redirect_to dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), status: :see_other
  end

  def review
    @preview = find_preview
    @rows = LightekMail::ContactImport.classify(@account, @preview.contacts)
  end

  def import
    preview = find_preview
    row = team_mailbox(preview.team_mailbox_id)
    created, skipped = LightekMail::ContactImport.apply!(@account, preview)
    redirect_to dashboard_mail_contacts_path(account_id: @account.id, team_mailbox_id: row&.id),
      notice: "Imported #{created} contacts. Skipped #{skipped} duplicates and #{preview.invalid_rows} unreadable rows.", status: :see_other
  end

  def suggestions
    query = params[:q].to_s.strip.downcase.slice(0, 100)
    return render json: [] if query.length < 2

    matches = LightekMail::Contact.for_mailbox(@account).search(query).order(:name, :id).limit(25)
    results = matches.flat_map do |contact|
      contact.emails.filter_map do |email|
        {name: contact.name, email: email} if contact.name.downcase.include?(query) || email.downcase.include?(query)
      end
    end
    render json: results.uniq { |entry| entry.fetch(:email).downcase }.first(10)
  end

  def edit; end

  def update
    data = params.require(:contact).permit(:name, :emails, :phones, :labels)
    attributes = LightekMail::ContactImport.normalize(name: data[:name], emails: data[:emails].to_s.lines,
      phones: data[:phones].to_s.lines, labels: data[:labels].to_s.lines)
    @account.with_lock { @contact.update!(attributes) }
    redirect_to contacts_path, notice: "Contact updated.", status: :see_other
  rescue ArgumentError => error
    flash.now[:alert] = error.message
    render :edit, status: :unprocessable_entity
  end

  private

  def load_account
    response.set_header("Cache-Control", "private, no-store")
    @account = LightekMail::Access.accounts(current_user).where(user_id: current_user.id).find(params.require(:account_id))
  end

  def load_contact
    @contact = LightekMail::Contact.for_mailbox(@account).find(params[:id])
  end

  def contacts_path
    dashboard_mail_contacts_path(account_id: @account.id)
  end

  def find_preview
    LightekMail::ContactPreview.available.where(account: @account).find(params[:id])
  end

  def team_mailbox(id)
    return if id.blank?

    row = LightekMail::TeamMigrationMailbox.where(mailbox_user_id: current_user.id, account: @account).find(id)
    row.authorize_upload!(row.migration.employer, @account)
    row
  end
end
