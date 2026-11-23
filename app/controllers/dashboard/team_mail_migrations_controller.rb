class Dashboard::TeamMailMigrationsController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_workspace
  before_action :load_migration, except: %i[index create]
  before_action :load_mailbox, only: %i[upload_archive retry_archive remove_archive]

  rescue_from LightekPeople::Access::Denied, LightekMail::Access::Denied do
    head :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    redirect_to(@migration ? dashboard_team_mail_migration_path(@migration) : dashboard_team_mail_migrations_path,
      alert: error.message, status: :see_other)
  end

  def index
    @migrations = migrations.order(created_at: :desc, id: :desc).limit(30)
  end

  def create
    migration = LightekMail::TeamMigrationMapping.create!(
      actor: current_user, name: params[:name], upload: params[:mapping]
    )
    redirect_to dashboard_team_mail_migration_path(migration), status: :see_other
  end

  def show
    @mailboxes = @migration.mailboxes.includes(mailbox_import: {archive_attachment: :blob}).order(:id)
  end

  def upload_archive
    LightekMail::MailboxImport.create_upload!(@mailbox.account, current_user, params[:archive], team_mailbox: @mailbox)
    back
  end

  def start_ready
    started = 0
    blocked = 0
    @migration.mailboxes.includes(:account, :mailbox_import).find_each do |mailbox|
      import = mailbox.mailbox_import
      next unless import&.importable?

      begin
        mailbox.authorize_upload!(current_user)
        import.start_import!
        if import.state == "queued"
          started += 1
        else
          blocked += 1
        end
      rescue ArgumentError, LightekMail::Access::Denied, ActiveRecord::RecordNotFound
        blocked += 1
      end
    end
    if blocked.positive?
      back(alert: "Queued #{started} mailbox imports. #{blocked} could not be queued. Review the affected rows.")
    else
      back(notice: "Queued #{started} mailbox imports.")
    end
  end

  def retry_archive
    @mailbox.authorize_upload!(current_user)
    archive.retry!
    back
  end

  def remove_archive
    archive.remove!
    back(notice: "Archive removed.")
  end

  private

  def load_workspace
    response.set_header("Cache-Control", "private, no-store")
    raise LightekPeople::Access::Denied unless current_user

    LightekMail::TeamMigration.workspace_for!(current_user)
  end

  def migrations
    LightekMail::TeamMigration.where(employer: current_user)
  end

  def load_migration
    @migration = migrations.find(params[:id])
  end

  def load_mailbox
    @mailbox = @migration.mailboxes.find(params[:mailbox_id])
  end

  def archive
    @mailbox.mailbox_import || raise(ActiveRecord::RecordNotFound)
  end

  def back(**flash_messages)
    redirect_to dashboard_team_mail_migration_path(@migration), status: :see_other, **flash_messages
  end
end
