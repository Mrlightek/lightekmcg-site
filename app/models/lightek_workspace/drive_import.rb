module LightekWorkspace
  class DriveImport < ApplicationRecord
    self.table_name = "lightek_shared_drive_imports"

    belongs_to :drive
    belongs_to :folder, class_name: "LightekWorkspace::DriveEntry", optional: true
    belongs_to :actor, class_name: "User"
    belongs_to :team_migration, class_name: "LightekMail::TeamMigration", optional: true, inverse_of: :drive_imports
    has_one_attached :archive

    def self.authorize!(drive, actor)
      unless drive.editable_by?(actor) && LightekTeam::Workspace.employers_for(actor).exists?(drive.employer_id)
        raise LightekPeople::Access::Denied
      end
    end

    def retryable?
      state == "failed" || (state.in?(%w[queued running]) && updated_at <= 20.minutes.ago)
    end

    def queue!
      with_lock do
        unless state == "preview" || retryable?
          raise ArgumentError, "This import is already queued or complete."
        end
        update!(state: "queued", run_token: SecureRandom.uuid, error_message: nil)
      end
      token = run_token
      return if DriveImportJob.perform_later(id, token)

      with_lock do
        update!(state: "failed", error_message: "The import could not be queued.") if run_token == token && state == "queued"
      end
    end
  end
end
