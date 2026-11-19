# frozen_string_literal: true
module Studio
  module Performance
    class Contact
      FACES={"front"=>[0,-1,0],"back"=>[0,1,0],"left"=>[-1,0,0],"right"=>[1,0,0],"top"=>[0,0,1],"bottom"=>[0,0,-1]}.freeze
      def self.static_cube?(object)
        definition=object.fetch("definition",{})
        (object["type"] || object["object_type"])=="cube" && !%w[character_profile character_key blocking_actor director_speaker body_part animation story_relation authoring_commands].any? { |key| definition[key].present? }
      end
      def self.targets(objects)
        objects.select { |object| static_cube?(object) && object.dig("definition","contact_response")!="counter_handoff" }.first(16).map { |object| {id:object.fetch("id").to_s,name:object.fetch("name"),faces:FACES.keys} }
      end
      def self.inputs(payload)
        return {} unless payload["contact"].present?
        raw=payload.fetch("contact")
        raise ArgumentError,"Choose a prop, face and hand for contact" unless raw.is_a?(Hash) && (raw.keys-%w[target_id face hand start reach hold release]).empty?
        id=raw.fetch("target_id").to_s;face=raw.fetch("face","front").to_s;hand=raw.fetch("hand","right").to_s
        raise ArgumentError,"Choose a scene prop" unless id.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
        raise ArgumentError,"Choose an available prop face and hand" unless FACES.key?(face) && %w[left right].include?(hand)
        timings=%w[start reach hold release].to_h do |key|
          value=Float(raw.fetch(key,{"start"=>1.1,"reach"=>0.5,"hold"=>0.5,"release"=>0.5}[key]))
          range=key=="start" ? (0.0..6.0) : key=="hold" ? (0.2..2.0) : (0.4..1.5)
          raise ArgumentError,"Use finite contact timing within the short-scene budget" unless value.finite? && range.cover?(value)
          [key,(value*12).round/12.0]
        end
        raise ArgumentError,"The complete contact must fit within eight seconds" if timings.values.sum>8
        {"contact"=>{"target_id"=>id,"face"=>face,"hand"=>hand}.merge(timings)}
      end
      def self.validate_target!(character,staging)
        return unless (cue=character["contact"])
        target=staging.fetch("objects").find { |object| object["id"].to_s==cue["target_id"] }
        raise ArgumentError,"Choose a static cube prop from this scene setup" unless target && static_cube?(target)
        if target.dig("definition","contact_response")=="counter_handoff" && staging["key"]!=SceneTemplates::HANDOFF_KEY
          raise ArgumentError,"Use the two-character counter handoff setup for this parcel"
        end
        %w[location rotation scale].each do |key|
          values=target.fetch("definition").fetch(key,key=="scale" ? [1,1,1] : [0,0,0])
          raise ArgumentError,"Contact targets need finite transforms" unless values.is_a?(Array) && values.size==3 && values.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=1000 }
          raise ArgumentError,"Contact prop scales must be positive (0.01–10)" if key=="scale" && !values.all? { |v| v.between?(0.01,10) }
        end
        raise ArgumentError,"Choose no added body action for a prop contact" unless character.fetch("body_action","still")=="still"
        if cue["hand"]=="right" && character["gesture"]=="wave_right"
          raise ArgumentError,"Choose no added arm gesture while that hand contacts a prop"
        end
        if character.fetch("entrance","none")!="none" && cue["start"]<1.0
          raise ArgumentError,"Start contact after the character has finished entering (at least 1 second)"
        end
      end
      def self.validate_profile!(character,profile)
        return unless (cue=character["contact"])
        raise ArgumentError,"This saved Cast has no bound #{cue['hand']} hand for contact. Build a new illustrated performer or register compatible reach bindings." unless profile.fetch("reach_bindings",{}).key?(cue["hand"])
      end
      def self.ending(character)
        cue=character["contact"];cue ? cue.values_at("start","reach","hold","release").sum : 0
      end
      def self.apply!(scene:,object:,character:)
        return unless (cue=character["contact"])
        scene.with_lock do
          return if object.reload.definition["prop_contact"]
          target=scene.scene_objects.find { |prop| prop.definition["template_source_object_id"]==cue["target_id"] }
          raise ArgumentError,"The saved contact prop is missing" unless target
          record=cue.except("target_id").merge("target_object_id"=>target.id,"point"=>FACES.fetch(cue["face"]))
          object.update!(definition:object.definition.merge("prop_contact"=>record))
          scene.update!(settings:scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0)+1))
        end
      end
    end
  end
end
