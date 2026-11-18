module PwaMemberStorageQuota
  extend ActiveSupport::Concern
  included { before_create :enforce_pwa_member_storage_quota }
  private
  def enforce_pwa_member_storage_quota
    return unless LightekPwa::SourceRuntime.member?
    connection = self.class.connection
    connection.execute('SELECT pg_advisory_xact_lock(5917013)') if connection.adapter_name == 'PostgreSQL'
    rows = self.class.all
    if LightekPwa::SourceRuntime.shared?
      owner = metadata['lightek_user_id']
      site = DymondSite::Site.find_by(id: metadata['lightek_site_id']) if metadata['lightek_site_id']
      site ||= LightekPwa::SourceRuntime.site
      raise LightekPwa::SourceRuntime::ReadOnly, 'The upload must belong to a shared hosting account' unless site && site.manifest.dig('pwa_member', 'hosting') == 'shared_account' && (!owner || owner.to_i == site.tenant_id)
      LightekPwa::SourceRuntime.with_site(site) { LightekPwa::SourceRuntime.writable! }
      self.metadata = metadata.merge('lightek_user_id' => site.tenant_id, 'lightek_site_id' => site.id)
      json = connection.adapter_name == 'PostgreSQL' ? 'metadata::jsonb' : 'metadata'
      rows = rows.where("CAST(#{json} ->> 'lightek_user_id' AS TEXT) = ?", site.tenant_id.to_s)
      limit = Integer(site.manifest.fetch('pwa_member').fetch('storage_bytes'))
    else
      limit = Integer(ENV.fetch('LIGHTEK_PWA_MEMBER_STORAGE_BYTES', '536870912'))
    end
    raise LightekPwa::SourceRuntime::ReadOnly, 'Your free storage allowance is full. Remove unused files or upgrade to dedicated hosting.' if rows.sum(:byte_size) + byte_size > limit
  end
end
