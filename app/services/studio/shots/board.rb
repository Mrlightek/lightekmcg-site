# frozen_string_literal: true
require "digest"

module Studio
  module Shots
    class Board
      KEY = /\A[a-zA-Z0-9_-]{8,100}\z/
      TRANSIENT = %w[shot_board shot_board_receipts workspace timeline music authoring_history authoring_redo native_revision].freeze

      def self.integer(value, minimum, maximum)
        raise ArgumentError, "Use a whole frame or object ID" unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
        number = Integer(value)
        raise ArgumentError, "Frame or object ID is outside its range" unless number.between?(minimum, maximum)
        number
      end

      def self.normalize(scene, rows)
        raise ArgumentError, "Use at most 64 shots per scene" unless rows.is_a?(Array) && rows.length <= 64
        objects = scene.scene_objects.reject { |o| o.definition["native_deleted"] }.index_by(&:id)
        shots = rows.map do |raw|
          raise ArgumentError, "Each shot must be an object" unless raw.is_a?(Hash)
          raw = raw.to_h.deep_stringify_keys
          id = raw.fetch("id").to_s
          name = raw.fetch("name").to_s.strip
          notes = raw.fetch("notes", "").to_s
          prompt = raw.fetch("prompt", "").to_s
          raise ArgumentError, "Give each shot a stable ID and a name of 1–120 characters" unless KEY.match?(id) && name.length.between?(1,120)
          raise ArgumentError, "Use up to 2000 characters for direction and generation prompts" if notes.length > 2000 || prompt.length > 2000
          first = integer(raw.fetch("frame_start"),1,216000)
          last = integer(raw.fetch("frame_end"),first,216000)
          raise ArgumentError, "Use at most 2400 frames per shot" if last-first+1 > 2400
          camera_id = integer(raw.fetch("camera_id"),1,2**63-1)
          raise ArgumentError, "Choose a camera in this scene" unless objects[camera_id]&.object_type == "camera"
          cast = raw.fetch("cast_ids",[])
          raise ArgumentError, "Choose up to sixteen placed Cast members" unless cast.is_a?(Array) && cast.length<=16
          cast = cast.map { |v| integer(v,1,2**63-1) }.uniq
          raise ArgumentError, "Choose Cast members placed in this scene" unless cast.all? { |id| objects[id]&.definition&.dig("character_profile") }
          {"id"=>id,"name"=>name,"notes"=>notes,"prompt"=>prompt,"camera_id"=>camera_id,"frame_start"=>first,"frame_end"=>last,"cast_ids"=>cast}
        end
        raise ArgumentError, "Shot IDs must be unique" unless shots.map { |s| s["id"] }.uniq.length==shots.length
        shots
      end

      def self.save(access:, payload:)
        scene = access.scene!(payload.fetch("scene_id"))
        key = payload.fetch("request_key").to_s
        raise ArgumentError, "A storyboard request key is required" unless KEY.match?(key)
        scene.with_lock do
          shots = normalize(scene,payload.fetch("shots"))
          digest = fingerprint(shots)
          receipts = scene.settings.fetch("shot_board_receipts",{})
          if (receipt=receipts[key])
            raise ArgumentError, "This storyboard key belongs to different edits" unless receipt["fingerprint"]==digest
            return receipt
          end
          expected_lock=Integer(payload.fetch("lock_version"))
          board_unchanged=payload.key?("board_revision") && integer(payload["board_revision"],0,2**31-1)==scene.settings.dig("shot_board","revision").to_i
          scene.lock_version=expected_lock unless board_unchanged
          revision = scene.settings.dig("shot_board","revision").to_i+1
          result = {"scene_id"=>scene.id,"revision"=>revision,"lock_version"=>scene.lock_version+1,"fingerprint"=>digest}
          scene.update!(settings:scene.settings.merge("shot_board"=>{"version"=>1,"revision"=>revision,"shots"=>shots},"shot_board_receipts"=>receipts.to_a.last(99).to_h.merge(key=>result)))
          result
        end
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError, "The scene changed. Refresh before saving the storyboard."
      end

      def self.find(scene, id)
        Array(scene.settings.dig("shot_board","shots")).find { |s| s["id"]==id.to_s } || raise(ArgumentError,"Choose a saved shot in this scene")
      end

      def self.snapshot(scene, id, base: nil)
        # Validate references again: a camera or cast object may have been removed
        # since the board was saved. The source scene is never changed here.
        shot = normalize(scene,[find(scene,id)]).first
        manifest = (base || Blender::ManifestBuilder.new(scene).call).deep_dup
        settings = manifest.fetch("scene").fetch("settings")
        settings.reject! { |k,_| TRANSIENT.include?(k) || k.end_with?("_receipts", "_requests", "_revision") }
        settings.merge!("active_camera_object_id"=>shot["camera_id"],"frame_start"=>shot["frame_start"],"frame_end"=>shot["frame_end"],"frame_current"=>shot["frame_start"])
        manifest["scene"]["objects"].reject! { |o| o.dig("definition","character_profile") && shot["cast_ids"].any? && !shot["cast_ids"].include?(o["id"]) }
        manifest["outputs"]={"blend"=>true,"animation"=>true,"bundle"=>scene.blender_bundle.attached?}
        digest = fingerprint([manifest,scene.blender_source.blob&.id,scene.blender_bundle.blob&.id])
        [manifest,{"shot_id"=>shot["id"],"shot_name"=>shot["name"],"shot_fingerprint"=>digest}]
      end

      def self.list(access:, scene_id:)
        scene=access.scene!(scene_id)
        shots=Array(scene.settings.dig("shot_board","shots"))
        ids=shots.map { |s| s["id"] }
        latest=ids.empty? ? [] : scene.studio_operations.where("metadata ->> 'shot_id' IN (?)",ids).group(Arel.sql("metadata ->> 'shot_id'")).maximum(:id).values
        operations=scene.studio_operations.where(id:latest).includes(artifacts: {file_attachment: :blob}).index_by { |o| o.metadata["shot_id"] }
        base=shots.empty? ? nil : Blender::ManifestBuilder.new(scene).call
        rows=shots.map do |shot|
          operation=operations[shot["id"]]
          begin
            _,metadata=snapshot(scene,shot["id"],base:base)
            stale=operation && operation.metadata["shot_fingerprint"]!=metadata["shot_fingerprint"]
            invalid=nil
          rescue ArgumentError => error
            stale=!!operation;invalid=error.message
          end
          shot.merge("render"=>operation && {"operation_id"=>operation.id,"status"=>operation.status,"error"=>operation.error_message,"stale"=>!!stale,
            "artifacts"=>operation.artifacts.select { |a| a.kind=="video" && a.file.attached? }.map { |a| {"id"=>a.id,"filename"=>a.filename,"url"=>Rails.application.routes.url_helpers.rails_blob_path(a.file,only_path:true)} }},"validation_error"=>invalid)
        end
        {scene_id:scene.id,lock_version:scene.lock_version,revision:scene.settings.dig("shot_board","revision").to_i,shots:rows}
      end

      def self.fingerprint(value)
        canonical = ->(v) { v.is_a?(Hash) ? v.keys.sort.to_h { |k| [k,canonical.call(v[k])] } : v.is_a?(Array) ? v.map { |x| canonical.call(x) } : v }
        Digest::SHA256.hexdigest(JSON.generate(canonical.call(value)))
      end

      def self.copy_settings(settings, object_ids)
        result=settings.except("shot_board_receipts")
        if settings["shot_board"]
          board=settings["shot_board"].deep_dup
          board["shots"].each do |shot|
            shot["camera_id"]=object_ids[shot["camera_id"]]
            shot["cast_ids"]=shot["cast_ids"].filter_map { |id| object_ids[id] }
          end
          result=result.merge("shot_board"=>board)
        end
        result
      end
    end
  end
end
