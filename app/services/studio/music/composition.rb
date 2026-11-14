# frozen_string_literal: true
module Studio
  module Music
    # Musical timing is in quarter-note beats. Rendered audio uses the regular asset pipeline.
    class Composition
      INSTRUMENTS = %w[kick snare hat clap bass keys pad lead sample].freeze
      DRUMS = %w[kick snare hat clap].freeze
      MAX_NOTES = 4096
      def self.normalize(raw, access:)
        raise ArgumentError,"Music source must be an object" unless raw.is_a?(Hash)
        data = raw.deep_stringify_keys
        raise ArgumentError, "Music project is too large" if data.to_json.bytesize > 1_000_000
        raise ArgumentError, "Unsupported music project version" unless [1,2,3].include?(integer(data.fetch("version", 1)))
        tempo = number(data.fetch("tempo", 100), 40, 240)
        bars = integer(data.fetch("bars", 4))
        raise ArgumentError, "Use 1–128 bars" unless bars.between?(1, 128)
        raise ArgumentError, "Keep this composition within ten minutes" if bars * 4 * 60 / tempo > 600
        tracks = data.fetch("tracks")
        raise ArgumentError,"Instrument tracks must be a list" unless tracks.is_a?(Array)
        raise ArgumentError, "Use 1–16 instrument tracks" unless tracks.length.between?(1, 16)
        total = 0
        normalized = tracks.map do |raw_track|
          raise ArgumentError,"Each instrument track must be an object" unless raw_track.is_a?(Hash)
          track = raw_track.deep_stringify_keys
          id = track.fetch("id").to_s
          raise ArgumentError, "Invalid instrument track ID" unless id.match?(/\A[a-zA-Z0-9_-]{1,60}\z/)
          instrument = track.fetch("instrument")
          raise ArgumentError, "Choose an available instrument" unless INSTRUMENTS.include?(instrument)
          notes = track.fetch("notes", [])
          raise ArgumentError,"Instrument notes must be a list" unless notes.is_a?(Array)
          total += notes.length
          raise ArgumentError, "Use at most #{MAX_NOTES} notes per composition" if total > MAX_NOTES
          notes = self.notes(notes,bars:bars,instrument:instrument)
          result = {"id"=>id, "name"=>track.fetch("name", instrument.capitalize).to_s.first(60), "instrument"=>instrument,
            "gain"=>number(track.fetch("gain", 0.75), 0, 1.5), "pan"=>number(track.fetch("pan", 0), -1, 1),
            "muted"=>ActiveModel::Type::Boolean.new.cast(track.fetch("muted", false)), "solo"=>ActiveModel::Type::Boolean.new.cast(track.fetch("solo", false)),
            "cutoff"=>number(track.fetch("cutoff", 18000), 100, 18000), "delay"=>number(track.fetch("delay", 0), 0, 0.6), "notes"=>notes}
          if instrument == "sample"
            asset = StudioAsset.for_actor(access).where(site_id:access.site_id,status: "ready", kind: "audio").find(integer(track.fetch("asset_id")))
            raise ArgumentError,"Use sample recordings up to two minutes; trim longer sources first" unless asset.metadata["duration"].to_f.between?(0.01,120)
            first = number(track.fetch("sample_in", 0), 0, 600)
            last = number(track.fetch("sample_out", [asset.metadata["duration"].to_f, 30].min), 0.01, 600)
            raise ArgumentError, "Choose a sample slice up to thirty seconds within the recording" unless last > first && last-first <= 30 && last <= asset.metadata["duration"].to_f + 0.001
            root = integer(track.fetch("root", 60))
            raise ArgumentError, "Sample root note must be between 0 and 127" unless root.between?(0, 127)
            result.merge!("asset_id"=>asset.id, "sample_in"=>first, "sample_out"=>last, "root"=>root)
          end
          result
        end
        raise ArgumentError, "Track IDs must be unique" unless normalized.map { |t| t["id"] }.uniq.length == normalized.length
        result={"version"=>integer(data.fetch("version",1)), "name"=>data.fetch("name", "Untitled music").to_s.first(120), "tempo"=>tempo, "bars"=>bars,
          "swing"=>number(data.fetch("swing", 0), 0, 0.5), "tracks"=>normalized}
        raise ArgumentError,"Reusable patterns require music source version 2" if result["version"]==1 && (Array(data["patterns"]).any? || Array(data["playlist"]).any?)
        result.merge!(Patterns.normalize(data,tracks:normalized,bars:bars)) if result["version"]>=2 || data.key?("patterns") || data.key?("playlist")
        result["automation"]=Automation.normalize(data.fetch("automation",[]),tracks:normalized,bars:bars,version:result["version"]) if result["version"]>=3 || data.key?("automation")
        result
      rescue KeyError, TypeError => error
        raise ArgumentError,"Music project contains missing or invalid fields: #{error.message}"
      rescue JSON::GeneratorError
        raise ArgumentError,"Music values must be finite numbers"
      end

      def self.notes(notes,bars:,instrument:)
        raise ArgumentError,"Instrument notes must be a list" unless notes.is_a?(Array) && notes.length<=MAX_NOTES
        notes = notes.map do |item|
          raise ArgumentError,"Each note must be an object" unless item.is_a?(Hash)
          note = item.deep_stringify_keys
          beat = number(note.fetch("beat"), 0, bars * 4)
          length = number(note.fetch("length", 0.25), 0.015625, 64)
          pitch = integer(note.fetch("pitch", 60))
          raise ArgumentError, "MIDI notes must be between 0 and 127" unless pitch.between?(0, 127)
          raise ArgumentError, "A note extends beyond the song" if beat >= bars * 4 || beat + length > bars * 4 + 0.000001
          {"beat"=>beat, "length"=>length, "pitch"=>pitch, "velocity"=>number(note.fetch("velocity", 0.8), 0.01, 1)}
        end.sort_by { |n| [n["beat"], n["pitch"]] }
        note_keys = notes.map { |n| [n["beat"], DRUMS.include?(instrument) ? nil : n["pitch"]] }
        raise ArgumentError, "Remove duplicate notes at the same beat and pitch" unless note_keys.uniq.length == note_keys.length
        notes
      end

      def self.save(access:, payload:)
        scene = access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        score = normalize(payload.fetch("composition"), access: access)
        scene.with_lock do
          scene.lock_version = integer(payload.fetch("lock_version"))
          revision = scene.settings.fetch("music_revision", 0) + 1
          scene.update!(settings: scene.settings.merge("music"=>score, "music_revision"=>revision))
          {scene_id: scene.id, lock_version: scene.lock_version, composition: score, revision: revision}
        end
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError, "This scene changed in another editor. Your music draft is still open; reload before saving over a newer version."
      end

      # Replace the previous score's linked audio while retaining the editor's timing and mix.
      def self.place(access:, payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        asset=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"audio",status:"ready").find(integer(payload.fetch("asset_id")))
        scene.with_lock do
          revision=integer(payload.fetch("revision"))
          raise ArgumentError,"The music changed after this bounce. Save and bounce the current source." unless revision==scene.settings.fetch("music_revision",0)
          prior=scene.settings.fetch("music_mix",{})
          timeline=scene.settings.fetch("timeline",{"output"=>"video","width"=>1280,"height"=>720,"clips"=>[]}).deep_dup
          if prior["asset_id"]==asset.id && prior["revision"]==revision && timeline["clips"].any? { |c|c["asset_id"]==asset.id }
            return {scene_id:scene.id,lock_version:scene.lock_version,timeline:timeline}
          end
          scene.lock_version=integer(payload.fetch("lock_version"))
          duration=asset.metadata["duration"].to_f
          raise ArgumentError,"This mix has no usable audio duration" unless duration.finite? && duration>0 && duration<=600
          previous=StudioAsset.for_actor(access).find_by(id:prior["asset_id"])
          linked=timeline["clips"].select { |c|prior["asset_id"] && c["asset_id"]==prior["asset_id"] }
          if linked.any?
            linked.each do |clip|
              whole=previous && clip.fetch("in",0).to_f==0 && (clip["out"].to_f-previous.metadata["duration"].to_f).abs<0.05
              clip["out"]=duration if whole
              clip["asset_id"]=asset.id
            end
          else
            occupied=timeline["clips"].map { |c|integer(c.fetch("track",0)) }
            track=(0..15).find { |id|!occupied.include?(id) }
            raise ArgumentError,"Free an audio track before adding this score" unless track
            timeline["clips"]<<{"asset_id"=>asset.id,"in"=>0,"out"=>duration,"start"=>0,"track"=>track,"gain"=>1}
          end
          assets=StudioAsset.for_actor(access).where(id:timeline["clips"].map { |c|c["asset_id"] }).index_by(&:id)
          normalized=Studio::Editing::Timeline.normalize(timeline,assets:assets)
          scene.update!(settings:scene.settings.merge("timeline"=>normalized,"music_mix"=>{"asset_id"=>asset.id,"revision"=>revision}))
          {scene_id:scene.id,lock_version:scene.lock_version,timeline:normalized}
        end
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The episode edit changed. Refresh it before placing this music mix."
      end

      def self.integer(value)
        n=Integer(value)
        raise ArgumentError,"Use a whole number for bars, MIDI pitch and revisions" unless Float(value)==n
        n
      end

      def self.number(value, min, max)
        n = Float(value)
        raise ArgumentError, "Music value must be between #{min} and #{max}" unless n.finite? && n.between?(min, max)
        n
      end
    end
  end
end
