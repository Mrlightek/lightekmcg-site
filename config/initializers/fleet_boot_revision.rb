require "open3"
Rails.application.config.after_initialize do |application|
  # Capture once per process. Reading HEAD on every request could incorrectly
  # report new code while an old Passenger worker still serves requests.
  output, status = Open3.capture2("git", "-C", Rails.root.to_s, "rev-parse", "HEAD", err: File::NULL)
  application.config.x.fleet_boot_revision = output.strip if status.success? && output.strip.match?(/\A[a-f0-9]{40}\z/)
rescue SystemCallError
  application.config.x.fleet_boot_revision = nil
end
