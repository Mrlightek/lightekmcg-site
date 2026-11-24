class Dashboard::SharedDrivesController < Dashboard::SharedWorkspaceController
  before_action :load_drive, only: %i[show add download grant organize]
  rescue_from ActiveRecord::RecordInvalid, ArgumentError do |error|
    redirect_to(@drive ? dashboard_shared_drive_path(@drive, employer_id: @employer.id) : dashboard_shared_drives_path(employer_id: @employer.id),
      alert: error.message, status: :see_other)
  end

  def index
    @drives = drives.order(:name, :id).limit(100)
    @query = params[:q].to_s.strip.first(100)
    if @query.present?
      @results = search(LightekWorkspace::DriveEntry.where(drive_id: drives.select(:id)), @query)
        .includes(:drive, :office_file).order(:name).limit(100)
    end
  end

  def create
    owner!
    drive = drives.create!(name: params.require(:name))
    redirect_to dashboard_shared_drive_path(drive, employer_id: @employer.id), status: :see_other
  end

  def show
    @folder = @drive.entries.where(folder: true).find(params[:folder]) if params[:folder].present?
    @query = params[:q].to_s.strip.first(100)
    scope = @query.present? ? search(@drive.entries, @query) : @drive.entries.where(parent: @folder)
    @entries = scope.includes(:parent, :office_file).order(folder: :desc, name: :asc, id: :asc).limit(100)
    @folders = @drive.entries.where(folder: true).order(:name, :id).limit(100) if @editor
    @coworkers = @workspace.roster.where.not(id: @employer.id).order(:first_name, :last_name) if @owner
  end

  def add
    raise LightekPeople::Access::Denied unless @editor

    attrs = params.require(:entry).permit(:name, :parent_id, :upload)
    folder = @drive.entries.where(folder: true).find(attrs[:parent_id]) if attrs[:parent_id].present?
    upload = attrs[:upload]
    raise ArgumentError, 'Choose a file up to 25 MB.' if upload && (!upload.respond_to?(:original_filename) || upload.size > 25.megabytes)

    @drive.with_lock do
      raise LightekPeople::Access::Denied unless @drive.editable_by?(current_user)

      @drive.entries.create!(parent: folder, creator: current_user, folder: upload.nil?, upload: upload,
        name: attrs[:name].presence || upload&.original_filename)
    end
    redirect_to dashboard_shared_drive_path(@drive, employer_id: @employer.id, folder: folder&.id), status: :see_other
  end

  def organize
    @drive.with_lock do
      raise LightekPeople::Access::Denied unless @drive.editable_by?(current_user)

      entry = @drive.entries.find(params[:entry_id])
      attrs = params.require(:entry).permit(:name, :parent_id)
      parent = @drive.entries.where(folder: true).find(attrs[:parent_id]) if attrs[:parent_id].present?
      ancestor = parent
      while ancestor
        raise ArgumentError, 'A folder cannot be moved into itself or one of its subfolders.' if ancestor.id == entry.id

        ancestor = ancestor.parent
      end
      entry.update!(name: entry.office_file ? entry.name : attrs[:name], parent: parent)
      redirect_to dashboard_shared_drive_path(@drive, employer_id: @employer.id, folder: entry.parent_id), status: :see_other
    end
  end

  def download
    entry = @drive.entries.where(folder: false).find(params[:entry_id])
    raise ActiveRecord::RecordNotFound unless entry.upload.attached?

    send_data entry.upload.download, filename: entry.name, type: 'application/octet-stream', disposition: 'attachment'
  end

  def grant
    owner!
    attrs = params.require(:member).permit(:user_id, :role)
    user = @workspace.roster.where.not(id: @employer.id).find(attrs[:user_id])
    @drive.with_lock do
      scope = @drive.members.where(user: user)
      attrs[:role] == 'remove' ? scope.delete_all : (scope.first || scope.new).update!(role: attrs[:role])
    end
    redirect_to dashboard_shared_drive_path(@drive, employer_id: @employer.id), status: :see_other
  end

  private

  def drives
    LightekWorkspace::Drive.accessible_to(current_user, @employer)
  end

  def load_drive
    @drive = drives.find(params[:id])
    @editor = @drive.editable_by?(current_user)
  end

  def search(scope, query)
    scope.where('LOWER(name) LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%")
  end
end
