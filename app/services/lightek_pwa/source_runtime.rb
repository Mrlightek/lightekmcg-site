module LightekPwa
  class SourceRuntime
    class ReadOnly < StandardError; end
    MEMBER_STUDIO_ACTIONS = %w[look_status look_save material_save motion_save performance_analyze performance_analysis
      shots_save shots_list starter_scene_create starter_scene_status ai_setup_status ai_status ai_jobs project_create
      artifact_use music_save music_place cast_create cast_retry cast_register cast_place performance_save performance_remove
      performance_preview content_generate writing_profiles scene_save project_delete template_save template_use
      operations_list artifact_reuse artifact_publish visual_save asset_import assets_list timeline_save timeline_quote
      asset_place asset_use asset_publish asset_retry library_apply blender_template_use blender_camera_create
      blender_camera_save blender_demo_import blender_prepare blender_preset_use blender_object_save blender_preview
      blender_runtime_status blender_create blender_asset_save blender_authoring_edit blender_authoring_preview].map { |action| "studio.workspace.#{action.tr('_', '.')}" }.freeze
    def self.member? = ENV['LIGHTEK_PWA_MEMBER_BACKEND'] == 'true'
    def self.frozen? = File.exist?(Rails.root.join('tmp/pwa-migration.lock'))
    def self.writable!
      raise ReadOnly, 'Your backend is moving. Please retry when migration finishes.' if frozen? && !Thread.current[:pwa_transfer_control]
    end
    def self.control
      old = Thread.current[:pwa_transfer_control]; Thread.current[:pwa_transfer_control] = true
      yield
    ensure
      Thread.current[:pwa_transfer_control] = old
    end
    def self.allowed_request?(request)
      return false if frozen?
      path = request.path
      return true if path.start_with?('/lightek/', '/api/lightek/', '/pwa/member-session', '/identity/', '/session', '/passwords', '/account-setup', '/__lightek/', '/up')
      if path == '/api/nevaeh/execute'
        capability = request.request_parameters['capability'].to_s
        return MEMBER_STUDIO_ACTIONS.include?(capability) if capability.start_with?('studio.workspace.')
        return capability.match?(/\A(?:community\.|social\.|messages\.|messaging\.|studio\.(?:workspace\.|pwa\.|scene_object\.|scene\.))/)
      end
      return true if path.start_with?('/api/nevaeh/bootstrap', '/api/nevaeh/executions/')
      return true if request.get? && %w[/dashboard/pages /dashboard/business /dashboard/settings /dashboard/client-home].include?(path)
      path.start_with?('/dashboard/live', '/dashboard/identity')
    end
  end
end
