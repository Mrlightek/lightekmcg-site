# frozen_string_literal: true

class Dashboard::ExecutiveWorkController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :private_workspace
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekMail::Submission::Unavailable,
    Studio::Broadcasting::HostedPrograms::Unavailable, LightekReservations::Federation::Client::Unavailable, with: :invalid_request

  def index
    @record = records.find(params[:item]) if params[:item].present?
    @records = records.includes(:owner, :assignee).order(Arel.sql("CASE WHEN status = 'closed' THEN 1 ELSE 0 END"), :due_at, :id).limit(100)
    if @executive
      @staff = employee_roster.order(:first_name, :last_name)
      @phone_route = NevaehExecutivePhoneRoute.find_by(owner: current_user)
    end
    if @record&.owner_id == current_user.id
      @mailboxes = LightekMail::Access.accounts(current_user).where(user: current_user).order(:address)
      if @record.kind == 'screening'
        sites = LightekSettings::WebsiteIdentity.sites_for(current_user).where(tenant: current_user)
        @screenings = Studio::Broadcasting::ProgramLicense.where(licensee_site: sites).order(:title).limit(150).select(&:web_screening_allowed?)
      end
    end
  end

  def create
    executive!
    values = params.require(:executive_case).permit(:title, :kind, :details, :due_at, :assignee_id, :material)
    assignee = employee_roster.find(values[:assignee_id]) if values[:assignee_id].present?
    @record = NevaehExecutiveCase.create!(values.except(:assignee_id).merge(owner: current_user, assignee: assignee,
      status: assignee ? 'in_review' : 'open'))
    back('Work item saved.')
  end

  def configure_phone
    executive!
    values = params.require(:executive_phone).permit(:assignee_id, :signing_secret)
    assignee = employee_roster.find(values[:assignee_id]) if values[:assignee_id].present?
    NevaehOs::PhoneIntake.configure!(owner: current_user, assignee: assignee, secret: values.require(:signing_secret))
    redirect_to dashboard_executive_work_path, notice: 'Phone intake configured.', status: :see_other
  end

  def route
    executive!
    @record = records.where(owner: current_user).find(params[:id])
    assignee = employee_roster.find(params.require(:assignee_id))
    @record.with_lock do
      require_open!
      @record.update!(assignee: assignee, status: 'in_review', reviewer: nil, reviewed_at: nil, review_note: nil)
    end
    back('Routed to the selected teammate.')
  end

  def review
    @record = records.find(params[:id])
    note = params.require(:review_note).to_s.strip
    raise ArgumentError, 'Enter the review notes.' if note.blank?
    status = params.require(:decision)
    raise ArgumentError, 'Choose Reviewed or Needs changes.' unless %w[reviewed needs_changes].include?(status)

    @record.with_lock do
      records.find(@record.id)
      require_open!
      @record.update!(status: status, review_note: note, reviewer: current_user, reviewed_at: Time.current)
    end
    back('Review recorded.')
  end

  def close
    executive!
    @record = records.where(owner: current_user).find(params[:id])
    reference = params[:reference].to_s.strip
    @record.with_lock do
      require_open!
      if %w[expense contract].include?(@record.kind) && @record.status != 'reviewed'
        raise ArgumentError, 'Record a completed review before closing an expense or contract.'
      end
      if %w[travel screening expense contract].include?(@record.kind) && reference.blank?
        raise ArgumentError, 'Enter a confirmation, delivery, or review reference before closing this item.'
      end
      values = params.permit(:completion_material).merge(status: 'closed', reference: reference)
      @record.update!(values)
    end
    back('Work item closed.')
  end

  def dispatch_material
    executive!
    @record = records.where(owner: current_user).find(params[:id])
    values = params.require(:executive_delivery).permit(:mailbox_id, :recipient, :instructions, :license_id)
    delivery = NevaehOs::ExecutiveDelivery.new(actor: current_user, mailbox_id: values.require(:mailbox_id))
    @record.with_lock do
      message = case @record.kind
      when 'travel'
        delivery.request_booking!(record: @record, recipient: values.require(:recipient), instructions: values.require(:instructions))
      when 'screening'
        delivery.send_screening!(record: @record, recipient: values.require(:recipient), license_id: values.require(:license_id))
      else
        raise ActiveRecord::RecordNotFound
      end
      @record.update!(delivery_message: message)
    end
    back('Message queued in Lightek Mail.')
  end

  def material
    record = records.find(params[:id])
    attachment = params[:completion] == '1' ? record.completion_material : record.material
    raise ActiveRecord::RecordNotFound unless attachment.attached?

    send_data attachment.download, filename: attachment.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  private

  def private_workspace
    response.headers['Cache-Control'] = 'private, no-store'
    raise LightekPeople::Access::Denied unless LightekPeople::LifecycleAccess.active?(current_user)

    @executive = NevaehOs::ExecutiveBrief.available_to?(current_user)
  end

  def executive!
    raise LightekPeople::Access::Denied unless @executive
  end

  def employee_roster
    staff = LightekPeople::Employment.active.where(employer: current_user).select(:worker_id)
    User.where(id: staff, access_suspended_at: nil)
  end

  def records = NevaehExecutiveCase.visible_to(current_user)

  def require_open!
    raise ArgumentError, 'This work item is already closed.' if @record.status == 'closed'
  end

  def back(notice)
    redirect_to dashboard_executive_work_path(item: @record.id), notice: notice, status: :see_other
  end

  def invalid_request(error)
    redirect_to dashboard_executive_work_path(item: @record&.id), alert: error.message, status: :see_other
  end
end
