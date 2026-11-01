# frozen_string_literal: true
require "digest"
require "json"
module NevaehIntelligences
  module StructuredWorkers
    class CreateMovieProject
      ACTION = "studio.project.from_template"
      RANGES = {"fps" => [1, 120], "resolution_x" => [64, 4096], "resolution_y" => [64, 4096],
        "duration_seconds" => [1, 1800], "lens" => [1, 1200], "aperture_fstop" => [0.1, 128]}.freeze

      def self.values!(inputs)
        values = inputs.fetch("data").to_h
        raise StructuredTicket::Invalid, "Supply only the movie template's supported settings" unless values.keys.sort == RANGES.keys.sort
        values.to_h do |key, raw|
          value = Float(raw)
          raise StructuredTicket::Invalid, "#{key} is outside the supported range" unless value.finite? && value.between?(*RANGES.fetch(key))
          if %w[fps resolution_x resolution_y].include?(key)
            raise StructuredTicket::Invalid, "#{key} must be a whole number" unless value == value.to_i
            value = value.to_i
          end
          [key, value]
        end
      rescue ArgumentError, TypeError
        raise StructuredTicket::Invalid, "Movie settings must contain valid numbers"
      end

      def self.preset!(inputs)
        key = inputs.fetch("preset_key")
        definition = KnowledgeProcedures.fetch!(ACTION)
        source = Studio::NativeBlender::MediaPresets.resolve(key)
        digest = Digest::SHA256.hexdigest(JSON.generate(KnowledgeProcedures.canonical(source)))
        raise StructuredTicket::Invalid, "This media preset revision has not been taught in the KB" unless definition.fetch("preset_sources", {})[key] == digest
        key
      end

      def self.perform(inputs, actor:, ticket:)
        values = values!(inputs)
        key = preset!(inputs)
        site = StructuredActions.site(actor, inputs)
        Studio::Broadcasting::Access.authorize!(actor, site)
        access = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => site.id)
        request_key = "nevaeh_#{ticket.id}_#{Digest::SHA256.hexdigest(JSON.generate(KnowledgeProcedures.canonical(inputs)))}"
        result = Studio::NativeBlender::PresetUse.call(access: access, payload: {"key" => key, "mode" => "new_project", "name" => inputs.fetch("name"), "request_key" => request_key}).deep_stringify_keys
        project = access.projects.find(result.fetch("project_id"))
        project.studio_scenes.order(:id).each do |scene|
          scene.update!(settings: scene.settings.merge(values.slice("fps", "resolution_x", "resolution_y")).merge("fps_base" => 1.0,
            "frame_start" => 1, "frame_current" => 1, "frame_end" => (values.fetch("duration_seconds") * values.fetch("fps")).round))
          scene.scene_objects.where(object_type: "camera").each do |camera|
            settings = Studio::NativeBlender::CameraSettings.normalize(values.slice("lens", "aperture_fstop"), base: camera.definition)
            camera.update!(definition: camera.definition.merge(settings))
          end
        end
        {"project_id" => project.id, "production_id" => project.productions.first!.id,
          "default_scene_id" => project.studio_scenes.order(:id).first!.id, "scene_ids" => project.studio_scenes.order(:id).pluck(:id), "preset_key" => key}
      end

      def self.verify!(inputs, output, actor:)
        values = values!(inputs)
        key = preset!(inputs)
        site = StructuredActions.site(actor, inputs)
        Studio::Broadcasting::Access.authorize!(actor, site)
        access = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => site.id)
        project = access.projects.find(output.fetch("project_id"))
        production = project.productions.find(output.fetch("production_id"))
        source = Studio::NativeBlender::MediaPresets.resolve(key)
        scenes = project.studio_scenes.order(:id).to_a
        count = Studio::NativeBlender::MediaPresets.segments(source).first(100).size
        expected_objects = Studio::NativeBlender::MediaPresets.compile(key).fetch("objects").size
        raise StructuredTicket::Invalid, "Movie project acceptance failed" unless project.name == inputs.fetch("name") && project.site_id == site.id && project.owner_id == actor.id &&
          scenes.size == count && scenes.map(&:id) == output.fetch("scene_ids") && scenes.first.id == output.fetch("default_scene_id")
        scenes.each do |scene|
          raise StructuredTicket::Invalid, "Movie scene settings failed acceptance" unless scene.production_id == production.id &&
            values.slice("fps", "resolution_x", "resolution_y").all? { |field, value| scene.settings[field] == value } &&
            scene.settings["frame_end"] == (values.fetch("duration_seconds") * values.fetch("fps")).round && scene.scene_objects.count == expected_objects
          cameras = scene.scene_objects.where(object_type: "camera").to_a
          raise StructuredTicket::Invalid, "Movie cameras failed acceptance" unless cameras.any? && cameras.all? { |camera|
            camera.definition["lens"] == values.fetch("lens") && camera.definition["aperture_fstop"] == values.fetch("aperture_fstop") }
        end
        true
      end
    end
  end
end
