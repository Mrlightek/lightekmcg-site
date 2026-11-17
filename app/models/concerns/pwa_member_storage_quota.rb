module PwaMemberStorageQuota
  extend ActiveSupport::Concern
  included { before_create :enforce_pwa_member_storage_quota }
  private
  def enforce_pwa_member_storage_quota
    return unless LightekPwa::SourceRuntime.member?
    connection = self.class.connection
    connection.execute('SELECT pg_advisory_xact_lock(5917013)') if connection.adapter_name == 'PostgreSQL'
    limit = Integer(ENV.fetch('LIGHTEK_PWA_MEMBER_STORAGE_BYTES', '536870912'))
    raise LightekPwa::SourceRuntime::ReadOnly, 'Your free storage allowance is full. Remove unused files or upgrade your backend.' if self.class.sum(:byte_size) + byte_size > limit
  end
end
