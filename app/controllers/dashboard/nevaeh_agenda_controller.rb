# frozen_string_literal: true

class Dashboard::NevaehAgendaController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :authorize_agenda!
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_item
  rescue_from ActiveRecord::StaleObjectError do
    redirect_to dashboard_nevaeh_agenda_path, alert: 'This entry changed. Open it again to edit the latest version.'
  end

  def index
    @item = params[:edit].present? ? agenda.open_items.find(params[:edit]) : agenda.new(category: 'meeting')
    load_agenda
  end

  def create
    @item = agenda.create!(item_params.except(:lock_version))
    save_notice
  end

  def update
    @item = agenda.open_items.find(params[:id])
    @item.update!(item_params.merge(lock_version: params.require(:executive_item).require(:lock_version)))
    save_notice
  end

  def close
    item = agenda.find(params[:id])
    item.with_lock { item.update!(closed_at: Time.current) unless item.closed_at? }
    redirect_to dashboard_nevaeh_agenda_path, notice: 'Agenda entry closed.', status: :see_other
  end

  private

  def authorize_agenda!
    response.set_header('Cache-Control', 'private, no-store')
    head :forbidden unless NevaehOs::ExecutiveBrief.available_to?(current_user)
  end

  def agenda
    NevaehAgendaItem.where(user: current_user)
  end

  def item_params
    params.require(:executive_item).permit(:title, :category, :starts_at, :ends_at, :notes, :lock_version)
  end

  def load_agenda
    now = Time.current
    open = agenda.open_items
    @upcoming = open.where('ends_at > ?', now).order(:starts_at, :id).limit(60)
    @overdue = open.where('ends_at <= ?', now).order(ends_at: :desc, id: :desc).limit(30)
    @recently_closed = agenda.where.not(closed_at: nil).order(closed_at: :desc).limit(10)
  end

  def save_notice
    overlaps = @item.overlap_count
    message = overlaps.positive? ? "Saved. This overlaps #{helpers.pluralize(overlaps, 'agenda entry')}." : 'Agenda entry saved.'
    redirect_to dashboard_nevaeh_agenda_path, notice: message, status: :see_other
  end

  def invalid_item(error)
    @item = error.record
    load_agenda
    render :index, status: :unprocessable_entity
  end
end
