class Dashboard::SharedDriveImportsController < Dashboard::SharedWorkspaceController
  before_action :load_drive
  before_action :load_import, only: %i[show start destroy]

  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    destination = @import ? show_path : dashboard_shared_drive_imports_path(@drive, employer_id: @employer.id)
    redirect_to destination, alert: error.message, status: :see_other
  end

  def index
    @folder = @drive.entries.where(folder: true).find(params[:folder]) if params[:folder].present?
    @folders = @drive.entries.where(folder: true).order(:name, :id).limit(100).to_a
    @folders << @folder if @folder && !@folders.include?(@folder)
    @imports = imports.order(created_at: :desc, id: :desc).limit(20)
  end

  def create
    folder = @drive.entries.where(folder: true).find(params[:folder]) if params[:folder].present?
    @import = LightekWorkspace::DriveArchive.preview!(drive: @drive, folder: folder, actor: current_user, upload: params[:archive])
    redirect_to show_path, status: :see_other
  end

  def show; end

  def start
    @import.queue!
    redirect_to show_path, status: :see_other
  end

  def destroy
    @import.with_lock do
      if @import.state.in?(%w[queued running]) && !@import.retryable?
        raise ArgumentError, "Wait for this ZIP import to finish."
      end
      @import.destroy!
    end
    redirect_to dashboard_shared_drive_path(@drive, employer_id: @employer.id, folder: @import.folder_id), status: :see_other
  end

  private

  def load_drive
    @drive = LightekWorkspace::Drive.accessible_to(current_user, @employer).find(params[:drive_id])
    LightekWorkspace::DriveImport.authorize!(@drive, current_user)
  end

  def load_import
    @import = imports.find(params[:id])
  end

  def imports
    LightekWorkspace::DriveImport.where(drive: @drive, actor: current_user)
  end

  def show_path
    dashboard_shared_drive_import_path(@drive, @import, employer_id: @employer.id)
  end
end
