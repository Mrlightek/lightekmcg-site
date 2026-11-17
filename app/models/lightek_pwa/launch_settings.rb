module LightekPwa
  # Installation-wide configuration. Never stored in an editable site manifest
  # or copied to a member server. Secret material belongs in Vault.
  class LaunchSettings < ApplicationRecord
    self.table_name = 'lightek_pwa_launch_settings'
    belongs_to :updated_by, class_name: 'User', optional: true
    ENV_KEYS = {
      'youtube_channel_id' => 'LIGHTEK_YOUTUBE_CHANNEL_ID',
      'youtube_credential_slug' => 'LIGHTEK_YOUTUBE_CREDENTIAL_SLUG',
      'youtube_uploads_enabled' => 'LIGHTEK_YOUTUBE_UPLOADS_ENABLED',
      'creator_support_enabled' => 'LIGHTEK_CREATOR_SUPPORT_ENABLED',
      'creator_payouts_enabled' => 'LIGHTEK_CREATOR_PAYOUTS_ENABLED',
      'view_payouts_enabled' => 'LIGHTEK_VIEW_PAYOUTS_ENABLED',
      'member_mail_enabled' => 'LIGHTEK_MEMBER_EMAIL_ENABLED'
    }.freeze
    FLAGS = ENV_KEYS.keys.grep(/_enabled\z/).freeze
    def self.snapshot
      saved = table_exists? ? find_by(id: 1)&.settings.to_h : {}
      ENV_KEYS.to_h do |key, env|
        [key, saved.key?(key) ? saved[key] : (FLAGS.include?(key) ? ENV[env] == 'true' : ENV[env].to_s)]
      end
    rescue ActiveRecord::NoDatabaseError
      ENV_KEYS.to_h { |key, env| [key, FLAGS.include?(key) ? ENV[env] == 'true' : ENV[env].to_s] }
    end
    def self.value(key) = snapshot.fetch(key.to_s)
    def self.enabled?(key) = value(key) == true
    def self.current!
      find_or_create_by!(id: 1)
    rescue ActiveRecord::RecordNotUnique
      find(1)
    end
  end
end
