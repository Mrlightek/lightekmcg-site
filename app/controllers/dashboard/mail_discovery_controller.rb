class Dashboard::MailDiscoveryController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_access
  before_action :load_matter, except: %i[index create_matter update_retention]

  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    back(alert: error.message)
  end

  def index
    prepare_index
  end

  def create_matter
    @access.require_owner!
    @matter = LightekMail::Matter.transaction do
      matter = @access.matters.create!(employer: current_user, name: params[:mail_matter_name].to_s.strip)
      audit!("matter_created", matter: matter)
      matter
    end
    back(notice: "Matter created.")
  end

  def update_retention
    mailbox = @access.own_mailboxes.find(params[:account_id])
    if params[:operation] == "remove"
      mailbox.with_lock do
        LightekMail::RetentionRule.find_by!(account: mailbox).destroy!
        audit!("retention_removed", account: mailbox)
      end
      return back(notice: "Retention rule removed.")
    end

    rule = LightekMail::RetentionRule.find_or_initialize_by(account: mailbox)
    rule.days = params[:days]
    raise ActiveRecord::RecordInvalid, rule unless rule.valid?

    if params[:operation] == "preview"
      cutoff = rule.cutoff
      retained = LightekMail::RetainedMessage.where(account: mailbox)
      on_hold = LightekMail::MatterHold.active.exists?(account: mailbox)
      @retention_preview = {mailbox: mailbox, days: rule.days, on_hold: on_hold,
        active: mailbox.messages.discoverable.where(LightekMail::Message.discovery_date.gt(cutoff)).count,
        retained: retained.where("sent_or_received_at > ?", cutoff).count,
        expiring: on_hold ? 0 : retained.where(sent_or_received_at: (..cutoff)).count}
      prepare_index
      return render :index
    end
    raise ArgumentError, "Choose preview or save." unless params[:operation] == "save"

    mailbox.with_lock do
      LightekMail::RetentionRule.find_or_initialize_by(account: mailbox).update!(days: rule.days)
      audit!("retention_saved", account: mailbox, details: {days: rule.days})
    end
    back(notice: "Retention rule saved.")
  end

  def show
    prepare_matter
  end

  def hold
    with_owned_mailbox do |mailbox|
      hold = @matter.holds.find_or_initialize_by(account: mailbox)
      raise ArgumentError, "This mailbox is already on hold in this matter." if hold.persisted? && !hold.released_at?

      hold.update!(released_at: nil)
      audit!("hold_placed", account: mailbox)
    end
    back(notice: "Mailbox hold placed.")
  end

  def release
    with_owned_mailbox do |mailbox|
      @matter.holds.active.find_by!(account: mailbox).update!(released_at: Time.current)
      audit!("hold_released", account: mailbox)
    end
    back(notice: "Hold released.")
  end

  def grant
    require_matter_owner!
    reviewer = @access.eligible_reviewers.find(params[:reviewer_id])
    @matter.with_lock do
      grant = @matter.reviewers.find_or_initialize_by(user: reviewer)
      unless grant.persisted?
        grant.save!
        audit!("reviewer_added", details: {reviewer_id: reviewer.id})
      end
    end
    back(notice: "Reviewer access granted.")
  end

  def revoke
    require_matter_owner!
    @matter.with_lock do
      reviewer = @matter.reviewers.find_by!(user_id: params[:reviewer_id])
      reviewer.destroy!
      audit!("reviewer_removed", details: {reviewer_id: reviewer.user_id})
    end
    back(notice: "Reviewer access removed.")
  end

  def search
    with_review_mailbox do |mailbox|
      @matches = discovery_search(mailbox).matches
      audit!("mail_searched", account: mailbox, count: @matches.size)
    end
    prepare_matter
    render :show
  end

  def export
    archive = with_review_mailbox do |mailbox|
      matches = discovery_search(mailbox).matches
      raise ArgumentError, "No messages matched this search." if matches.empty?

      bundle = LightekMail::DiscoveryExport.build(matches, matter: @matter, mailbox: mailbox.original_address.presence || mailbox.address)
      @access = LightekMail::DiscoveryAccess.new(current_user.reload)
      @access.matters.find(@matter.id)
      audit!("mail_exported", account: mailbox, count: matches.size, details: {sha256: Digest::SHA256.hexdigest(bundle)})
      bundle
    end
    send_data archive, type: "application/zip", disposition: "attachment", filename: "mail-matter-#{@matter.id}.zip"
  end

  private

  def load_access
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    @access = LightekMail::DiscoveryAccess.new(current_user)
  end

  def load_matter
    @matter = @access.matters.find(params[:id])
  end

  def require_matter_owner!
    raise LightekPeople::Access::Denied unless @matter.employer_id == current_user.id

    @access.require_owner!
  end

  def prepare_index
    @matters = @access.matters.order(created_at: :desc, id: :desc)
    return unless @access.owner?

    @mailboxes = @access.own_mailboxes.order(:address)
    @rules = LightekMail::RetentionRule.where(account_id: @mailboxes.select(:id)).includes(:account).order(:id)
    @activity = LightekMail::DiscoveryEvent.where(employer: current_user, matter_id: nil)
      .includes(:account, :actor).order(created_at: :desc, id: :desc).limit(25)
  end

  def prepare_matter
    @can_manage = @matter.employer_id == current_user.id && @access.owner?
    @holds = @matter.holds.active.where(account_id: matter_mailboxes.select(:id)).includes(:account).order(:id)
    @search_mailboxes = @can_manage ? @access.own_mailboxes.order(:address) : @holds.map(&:account)
    return unless @can_manage

    @available_mailboxes = @access.own_mailboxes.where.not(id: @holds.select(:account_id)).order(:address)
    @reviewers = @matter.reviewers.includes(:user).order(:id)
    @eligible_reviewers = @access.eligible_reviewers.where.not(id: @reviewers.select(:user_id)).order(:id)
    @activity = LightekMail::DiscoveryEvent.where(matter: @matter, employer_id: @matter.employer_id)
      .includes(:account, :actor).order(created_at: :desc, id: :desc).limit(25)
  end

  def with_owned_mailbox
    require_matter_owner!
    mailbox = @access.own_mailboxes.find(params[:account_id])
    mailbox.with_lock { yield mailbox }
  end

  def with_review_mailbox
    mailbox = matter_mailboxes.find(params[:account_id])
    mailbox.with_lock do
      @access = LightekMail::DiscoveryAccess.new(current_user.reload)
      @access.matters.find(@matter.id)
      @matter.holds.active.find_by!(account: mailbox) unless current_user.id == @matter.employer_id && @access.owner?
      @selected_mailbox = mailbox
      yield mailbox
    end
  end

  def matter_mailboxes
    LightekMail::DiscoveryAccess.mailboxes_for(@matter.employer_id)
  end

  def discovery_search(mailbox)
    LightekMail::DiscoverySearch.new(mailbox, query: params[:mail_discovery_query], from: params[:from_date], through: params[:through_date])
  end

  def audit!(action, matter: @matter, account: nil, count: nil, details: {})
    LightekMail::DiscoveryEvent.create!(employer_id: matter&.employer_id || current_user.id,
      matter: matter, account: account, actor: current_user, action: action, result_count: count, details: details)
  end

  def back(**flash_messages)
    redirect_to(@matter ? dashboard_mail_matter_path(@matter) : dashboard_mail_discovery_path,
      status: :see_other, **flash_messages)
  end
end
