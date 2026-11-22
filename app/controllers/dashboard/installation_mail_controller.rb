# frozen_string_literal: true

class Dashboard::InstallationMailController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_installation
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ArgumentError, LightekReservations::Federation::Client::Unavailable, with: :unavailable

  def index
    @folder = params[:folder].presence_in(%w[inbox sent outbox]) || 'inbox'
    @mailbox = @installation.request('installation/mail/inbox', folder: @folder)
    @message = @installation.request('installation/mail/read', id: params[:message]) if params[:message].present?
  end

  def send_message
    fields = params.require(:installation_message).permit(:to, :subject_line, :text, :request_key).to_h.symbolize_keys
    receipt = @installation.request('installation/mail/send', fields)
    redirect_to dashboard_installation_mail_path(folder: 'outbox', message: receipt.fetch('id')),
      notice: 'Message queued. Check its delivery status in the mailbox.', status: :see_other
  end

  private

  def load_installation
    response.headers['Cache-Control'] = 'private, no-store'
    @installation = LightekTeam::Installation.new(current_user)
    raise LightekPeople::Access::Denied unless @installation.owner? && !current_user.password_setup_required?
  end

  def unavailable(error)
    if action_name == 'index'
      flash.now[:alert] = error.message
      render :index, status: :service_unavailable
    else
      @folder = 'inbox'
      @draft = params[:installation_message]
      flash.now[:alert] = error.message
      render :index, status: :unprocessable_entity
    end
  end
end
