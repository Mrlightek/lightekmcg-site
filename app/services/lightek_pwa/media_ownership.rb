module LightekPwa
  class MediaOwnership
    def self.for(record, depth = 0)
      return if !record || depth > 5
      if record.respond_to?(:site_id) && record.site_id
        site = DymondSite::Site.find_by(id: record.site_id)
        return {'lightek_user_id' => site.tenant_id, 'lightek_site_id' => site.id} if site&.manifest.to_h.dig('pwa_member', 'hosting') == 'shared_account'
      end
      %i[studio_project studio_scene studio_operation creation_job].each do |name|
        next unless record.respond_to?(name)
        found = self.for(record.public_send(name), depth + 1)
        return found if found
      end
      nil
    end
    module Attachment
      def initialize(name, record, attachable)
        if SourceRuntime.shared? && attachable.is_a?(Hash) && attachable.key?(:io)
          ownership = MediaOwnership.for(record)
          raise SourceRuntime::ReadOnly, 'Generated media must belong to a shared hosting account' unless ownership
          attachable = attachable.merge(metadata: (attachable[:metadata] || {}).stringify_keys.merge(ownership))
        end
        super(name, record, attachable)
      end
    end
  end
end
