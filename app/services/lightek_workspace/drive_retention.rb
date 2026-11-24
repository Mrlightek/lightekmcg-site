module LightekWorkspace
  module DriveRetention
    BATCH_SIZE = 100
    DAY_RANGE = 1..36_500
    module_function

    def days!(value)
      days = Integer(value.to_s, 10, exception: false)
      raise ArgumentError, "Enter a whole number from 1 to 36,500 days." unless DAY_RANGE.cover?(days)

      days
    end

    def eligible(drive, days, now: Time.current)
      files = LightekOffice::SharedFile.where(drive_entry_id: drive.entries.where(folder: false).select(:id))
      LightekOffice::Revision.where(file_type: LightekOffice::SharedFile.polymorphic_name, file_id: files.select(:id))
        .where(created_at: ..(now - days.days))
    end

    def on_hold?(drive)
      DiscoveryDriveHold.active.exists?(drive: drive)
    end

    def expire!(now: Time.current)
      Drive.where.not(revision_retention_days: nil).find_each do |drive|
        drive.with_lock do
          days = drive.revision_retention_days
          next unless days && !on_hold?(drive)

          rows = eligible(drive, days, now: now).order(:created_at, :id).limit(BATCH_SIZE).to_a
          next if rows.empty?

          rows.each(&:destroy!)
          LightekMail::DiscoveryEvent.create!(employer_id: drive.employer_id, drive: drive,
            action: "drive_revisions_expired", result_count: rows.size, details: {days: days})
        end
      end
    end
  end
end
