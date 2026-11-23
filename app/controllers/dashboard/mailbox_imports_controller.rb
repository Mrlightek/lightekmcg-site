class Dashboard::MailboxImportsController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_mailbox
  before_action :load_import, only: %i[show approve start retry_import destroy]
  rescue_from LightekMail::Access::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
  rescue_from ArgumentError do |error|
    destination = @import ? dashboard_mailbox_import_path(@import, account_id: @account.id) : dashboard_mailbox_imports_path(account_id: @account.id)
    redirect_to destination, alert: error.message, status: :see_other
  end

  def index
    @accounts = @accounts.order(:address)
    @imports = imports.with_attached_archive.order(created_at: :desc, id: :desc).limit(30)
  end

  def create
    destination = @accounts.find(params.require(:destination_account_id))
    import = LightekMail::MailboxImport.create_upload!(destination, current_user, params[:archive])
    redirect_to dashboard_mailbox_import_path(import, account_id: destination.id), status: :see_other
  end

  def show; end

  def approve
    @import.approve_team_archive!(current_user)
    back
  end

  def start
    @import.start_import!
    back
  end

  def retry_import
    @import.retry!
    back
  end

  def destroy
    @import.remove!
    redirect_to dashboard_mailbox_imports_path(account_id: @account.id), notice: "Import archive removed.", status: :see_other
  end

  private

  def load_mailbox
    response.set_header("Cache-Control", "private, no-store")
    @accounts = LightekMail::Access.accounts(current_user)
    @account = @accounts.find(params.require(:account_id))
  end

  def imports
    LightekMail::MailboxImport.in_mailbox(@account)
  end

  def load_import
    @import = imports.with_attached_archive.find(params[:id])
  end

  def back
    redirect_to dashboard_mailbox_import_path(@import, account_id: @account.id), status: :see_other
  end
end
