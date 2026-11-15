# frozen_string_literal: true
module Studio
  module Director
    class Relationships
      def self.normalize(scene, rows)
        raise ArgumentError, 'Use up to 64 object relationships' unless rows.is_a?(Array) && rows.size<=64
        objects=scene.scene_objects.reject { |object| object.definition['native_deleted'] }.index_by(&:id)
        result=rows.map do |raw|
          raise ArgumentError, 'Use object_id, relative_to, offset and optional look_at' unless raw.is_a?(Hash) && (raw.keys-%w[object_id relative_to offset look_at look_at_offset facing_axis allow_close_contact personal_space depth_of_field aperture_fstop]).empty?
          id=Integer(raw.fetch('object_id'));parent=raw['relative_to'] && Integer(raw['relative_to'])
          target=raw['look_at'] && Integer(raw['look_at'])
          raise ArgumentError, 'Relationship targets must be different objects in this scene' unless objects[id] && (!parent || (objects[parent] && id!=parent)) && (parent || target) && (!target || (objects[target] && target!=id))
          axis=raw.fetch('facing_axis','-Y')
          raise ArgumentError,'Choose the character forward axis X, Y, -X or -Y' unless %w[X Y -X -Y].include?(axis)
          gaze_offset=raw.fetch('look_at_offset', objects[target]&.definition&.dig('character_profile') ? [0,0,1.4] : [0,0,0])
          raise ArgumentError,'Use a finite gaze offset of three values within ten units' unless gaze_offset.is_a?(Array) && gaze_offset.size==3 && gaze_offset.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=10 }
          raise ArgumentError,'Close-contact override must be a boolean' unless [true,false].include?(raw.fetch('allow_close_contact',false))
          space=Float(raw.fetch('personal_space',0.9));aperture=Float(raw.fetch('aperture_fstop',4))
          raise ArgumentError,'Personal space must be 0–5 metres and aperture f/1.2–22' unless space.finite? && space.between?(0,5) && aperture.finite? && aperture.between?(1.2,22)
          raise ArgumentError,'Depth of field must be a boolean' unless [true,false].include?(raw.fetch('depth_of_field',false))
          offset=raw.fetch('offset',[0,0,0])
          raise ArgumentError, 'Use a finite three-dimensional offset within 1000 units' unless offset.is_a?(Array) && offset.size==3 && offset.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=1000 }
          {'object_id'=>id,'relative_to'=>parent,'offset'=>offset,'look_at'=>target,'look_at_offset'=>gaze_offset,'facing_axis'=>axis,'allow_close_contact'=>raw.fetch('allow_close_contact',false),'personal_space'=>space,'depth_of_field'=>raw.fetch('depth_of_field',false),'aperture_fstop'=>aperture}.compact
        end
        raise ArgumentError, 'Each object can have one relative relationship' unless result.map { |row| row['object_id'] }.uniq.size==result.size
        # Include existing relationships when detecting dependency cycles.
        graph=objects.transform_values { |object| object.definition['story_relation'] }.compact.merge(result.index_by { |row| row['object_id'] })
        visiting={};visited={}
        visit=lambda do |id|
          raise ArgumentError, 'Relative parenting and tracking cannot form cycles' if visiting[id]
          return if visited[id]
          visiting[id]=true
          relation=graph[id]
          [relation&.fetch('relative_to',nil)].compact.uniq.each { |target| visit.call(target) }
          visiting.delete(id);visited[id]=true
        end
        graph.each_key { |id| visit.call(id) }
        result
      end
      def self.apply!(scene,rows)
        normalize(scene,rows).each do |row|
          object=scene.scene_objects.find(row['object_id'])
          object.update!(definition:object.definition.merge('story_relation'=>row.except('object_id')))
        end
        scene.update!(settings:scene.settings.merge('native_revision'=>scene.settings.fetch('native_revision',0).to_i+1)) if rows.any?
      end
    end
  end
end
