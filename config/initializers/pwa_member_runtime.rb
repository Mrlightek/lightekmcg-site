Rails.application.config.to_prepare do
  ActiveStorage::Blob.include(PwaMemberStorageQuota) unless ActiveStorage::Blob < PwaMemberStorageQuota
  klass = ActiveStorage::Attached::Changes::CreateOne
  klass.prepend(LightekPwa::MediaOwnership::Attachment) unless klass < LightekPwa::MediaOwnership::Attachment
end
