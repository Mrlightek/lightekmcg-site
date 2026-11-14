# frozen_string_literal: true
module Studio
  module Music
    class Patterns
      MAX_EXPANDED_NOTES=16_384
      def self.id(value)
        value=value.to_s
        raise ArgumentError,"Invalid music pattern or placement ID" unless value.match?(/\A[a-zA-Z0-9_-]{1,60}\z/)
        value
      end
      def self.normalize(data,tracks:,bars:)
        raw=data.fetch("patterns",[]);playlist=data.fetch("playlist",[])
        raise ArgumentError,"Use at most 32 patterns and 128 playlist placements" unless raw.is_a?(Array) && raw.length<=32 && playlist.is_a?(Array) && playlist.length<=128
        channels=tracks.index_by{|track|track["id"]};total=tracks.sum{|track|track["notes"].length}
        patterns=raw.map do |item|
          raise ArgumentError,"A pattern must be an object" unless item.is_a?(Hash)
          length=Composition.integer(item.fetch("bars",1))
          raise ArgumentError,"Patterns use 1–16 bars" unless length.between?(1,16)
          lanes=item.fetch("tracks")
          raise ArgumentError,"Pattern channels must be a list of at most sixteen lanes" unless lanes.is_a?(Array) && lanes.length<=16
          lanes=lanes.map do |lane|
            raise ArgumentError,"A pattern channel must be an object" unless lane.is_a?(Hash)
            channel=channels[lane.fetch("track_id")] || raise(ArgumentError,"A pattern references a missing instrument channel")
            raise ArgumentError,"Audio takes belong to the song, not reusable patterns" if channel["instrument"]=="recording" && lane.fetch("notes",[]).present?
            notes=Composition.notes(lane.fetch("notes",[]),bars:length,instrument:channel["instrument"])
            total+=notes.length
            raise ArgumentError,"Use at most 4096 source notes across song and patterns" if total>Composition::MAX_NOTES
            {"track_id"=>channel["id"],"notes"=>notes}
          end
          raise ArgumentError,"Pattern channels must be unique" unless lanes.map{|lane|lane["track_id"]}.uniq.length==lanes.length
          {"id"=>id(item.fetch("id")),"name"=>item.fetch("name","Pattern").to_s.first(60),"bars"=>length,"tracks"=>lanes}
        end
        raise ArgumentError,"Pattern IDs must be unique" unless patterns.map{|p|p["id"]}.uniq.length==patterns.length
        placements=playlist.map do |item|
          raise ArgumentError,"A playlist placement must be an object" unless item.is_a?(Hash)
          pattern=patterns.find{|p|p["id"]==item["pattern_id"]} || raise(ArgumentError,"Choose an existing music pattern")
          bar=Composition.integer(item.fetch("bar"));repeats=Composition.integer(item.fetch("repeat",1));transpose=Composition.integer(item.fetch("transpose",0))
          raise ArgumentError,"Place patterns inside the song with 1–32 repeats and transposition within two octaves" unless bar>=0 && repeats.between?(1,32) && transpose.between?(-24,24) && bar+pattern["bars"]*repeats<=bars
          {"id"=>id(item.fetch("id")),"pattern_id"=>pattern["id"],"bar"=>bar,"repeat"=>repeats,"transpose"=>transpose,
            "velocity"=>Composition.number(item.fetch("velocity",1),0,1),"muted"=>ActiveModel::Type::Boolean.new.cast(item.fetch("muted",false))}
        end
        raise ArgumentError,"Playlist placement IDs must be unique" unless placements.map{|p|p["id"]}.uniq.length==placements.length
        score={"tracks"=>tracks,"patterns"=>patterns,"playlist"=>placements}
        expand(score)
        {"patterns"=>patterns,"playlist"=>placements}
      end
      def self.expand(score)
        result=score.fetch("tracks").map(&:deep_dup);channels=result.index_by{|track|track["id"]}
        count=result.sum{|track|track["notes"].length};patterns=score.fetch("patterns",[]).index_by{|p|p["id"]}
        score.fetch("playlist",[]).each do |clip|
          pattern=patterns.fetch(clip["pattern_id"])
          clip["repeat"].times do |repeat|
            pattern["tracks"].each do |lane|
              channel=channels.fetch(lane["track_id"])
              lane["notes"].each do |note|
                count+=1;raise ArgumentError,"The expanded playlist exceeds 16384 notes" if count>MAX_EXPANDED_NOTES
                pitch=note["pitch"]+(Composition::DRUMS.include?(channel["instrument"]) ? 0 : clip["transpose"])
                raise ArgumentError,"A transposed pattern note is outside MIDI range" unless pitch.between?(0,127)
                next if clip["muted"] || clip["velocity"]==0
                channel["notes"]<<note.merge("beat"=>clip["bar"]*4+repeat*pattern["bars"]*4+note["beat"],"pitch"=>pitch,"velocity"=>note["velocity"]*clip["velocity"])
              end
            end
          end
        end
        result.each do |track|
          keys=track["notes"].map{|note|[note["beat"].round(6),Composition::DRUMS.include?(track["instrument"]) ? nil : note["pitch"]]}
          raise ArgumentError,"Pattern placements overlap notes on the same channel and pitch. Move the placement or clear those song notes." unless keys.uniq.length==keys.length
          track["notes"].sort_by!{|note|[note["beat"],note["pitch"]]}
        end
        result
      end
    end
  end
end
