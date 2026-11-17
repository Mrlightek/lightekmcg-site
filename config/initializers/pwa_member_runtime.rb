Rails.application.config.to_prepare do
  ActiveStorage::Blob.include(PwaMemberStorageQuota) unless ActiveStorage::Blob < PwaMemberStorageQuota
end
