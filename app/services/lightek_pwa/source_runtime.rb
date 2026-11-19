module LightekPwa
  class SourceRuntime
    class ReadOnly < StandardError; end
    MEMBER_STUDIO_ACTIONS = %w[sequence_catalog sequence_prepare sequence_status sequence_retry sequence_quote character_scene_catalog character_template_use character_scene_prepare character_scene_status character_scene_retry character_scene_quote workflow_status workflow_plan workflow_save workflow_quote render_checkout render_resume workflow_create look_status look_save material_save motion_save performance_analyze performance_analysis
      shots_save shots_list starter_scene_create starter_scene_status ai_setup_status ai_status ai_jobs project_create
      artifact_use music_save music_place cast_create cast_retry cast_register cast_place performance_save performance_remove
      performance_preview content_generate writing_profiles scene_save project_delete template_save template_use
      operations_list artifact_reuse artifact_publish visual_save asset_import assets_list timeline_save timeline_quote
      asset_place asset_use asset_publish asset_retry library_apply blender_template_use blender_camera_create
      blender_camera_save blender_demo_import blender_prepare blender_preset_use blender_object_save blender_preview
      blender_runtime_status blender_create blender_asset_save blender_authoring_edit blender_authoring_preview].map { |action| "studio.workspace.#{action.tr('_', '.')}" }.freeze
    def self.member? = ENV['LIGHTEK_PWA_MEMBER_BACKEND'] == 'true'
    def self.shared? = ENV['LIGHTEK_PWA_SHARED_HOSTING'] == 'true'
    def self.site = Thread.current[:pwa_member_site]
    def self.with_site(value)
      previous = site
      Thread.current[:pwa_member_site] = value
      yield
    ensure
      Thread.current[:pwa_member_site] = previous
    end
    def self.account_flag(key)
      raise ArgumentError, 'Invalid account key' unless key.to_s.match?(/\A[0-9a-f-]{36}\z/)
      Rails.root.join('tmp/pwa-accounts', "#{key}.lock")
    end
    def self.frozen?
      return true if File.exist?(Rails.root.join('tmp/pwa-migration.lock'))
      return true if site&.manifest.to_h.dig('pwa_member', 'moved_to').present?
      key = site&.manifest.to_h.dig('pwa_member', 'key')
      key.present? && File.exist?(account_flag(key))
    end
    def self.writable!(record: nil)
      return if Thread.current[:pwa_transfer_control]
      moved = false
      if shared? && record && DymondSite::Site.table_exists? && (%w[manifest tenant_type tenant_id] - DymondSite::Site.column_names).empty?
        account_site = if record.is_a?(DymondSite::Site)
          record
        elsif record.is_a?(User)
          DymondSite::Site.where(tenant: record).find { |row| row.manifest.dig('pwa_member', 'moved_to').present? }
        elsif record.is_a?(Profile)
          DymondSite::Site.where(tenant_type: 'User', tenant_id: record.user_id).find { |row| row.manifest.dig('pwa_member', 'moved_to').present? }
        else
          metadata = record.respond_to?(:metadata) && record.metadata.is_a?(Hash) ? record.metadata : {}
          info = MediaOwnership.for(record) || metadata
          DymondSite::Site.find_by(id: info['lightek_site_id']) if info['lightek_site_id']
        end
        moved = account_site&.manifest.to_h.dig('pwa_member', 'moved_to').present?
      end
      raise ReadOnly, 'Your account is moving to dedicated hosting. Please retry shortly.' if frozen? || moved
    end
    def self.control
      old = Thread.current[:pwa_transfer_control]; Thread.current[:pwa_transfer_control] = true
      yield
    ensure
      Thread.current[:pwa_transfer_control] = old
    end
    def self.allowed_request?(request)
      return true if request.get? && %w[/up /__lightek/release /__lightek/website-health /__lightek/site-health].include?(request.path)
      return false if frozen?
      path = request.path
      return true if request.get? && (path == '/' || path.start_with?('/site/'))
      return true if path.start_with?('/lightek/', '/api/lightek/', '/pwa/member-session', '/identity/', '/session', '/passwords', '/account/setup/', '/__lightek/', '/up')
      if path == '/api/nevaeh/execute'
        capability = request.request_parameters['capability'].to_s
        return true if capability == 'nevaeh.conversation'
        return MEMBER_STUDIO_ACTIONS.include?(capability) if capability.start_with?('studio.workspace.')
        return capability.match?(/\A(?:community\.|social\.|messages\.|messaging\.|studio\.(?:workspace\.|pwa\.|scene_object\.|scene\.))/)
      end
      return true if path.start_with?('/api/nevaeh/bootstrap', '/api/nevaeh/executions/')
      return true if request.get? && %w[/dashboard/pages /dashboard/business /dashboard/settings /dashboard/client-home /dashboard/commerce/orders].include?(path)
      path.start_with?('/dashboard/live', '/dashboard/identity')
    end
  end
end
