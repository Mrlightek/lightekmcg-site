# frozen_string_literal: true
module Studio
  module Director
    # A small explicit language over executable scene capabilities. Unrecognized
    # creative requests fail to Nevaeh's existing escalation policy; they are
    # never reported as generated assets or completed productions.
    class PwaIntent
      def self.resolve(instruction:, scene:, object_id: nil)
        text = instruction.to_s.strip
        if (match = text.match(/\A(?:add|create)\s+(?:an?\s+)?(cube|sphere|cylinder|plane|camera|point light|sun light|area light)(?:\s+named\s+(.+))?\z/i))
          type = match[1].downcase.tr(" ", "_")
          return ["create", { "name" => (match[2].presence || type.humanize).first(120), "object_type" => type, "allow_overlap" => true }]
        end
        object = scene.scene_objects.find(object_id) if object_id.present?
        if text.match?(/\Aduplicate (?:the )?selected(?: object)?\z/i)
          raise ArgumentError, "Select a scene element first" unless object
          return ["duplicate", { "object_id" => object.id }]
        end
        if text.match?(/\A(?:remove|delete) (?:the )?selected(?: object)?\z/i)
          raise ArgumentError, "Select a scene element first" unless object
          return ["destroy", { "object_id" => object.id }]
        end
        if (match = text.match(/\A(move|rotate|scale) (?:the )?selected(?: object)? to\s+(.+)\z/i))
          raise ArgumentError, "Select a scene element first" unless object
          values = match[2].split(",").map { |value| Float(value.strip) }
          raise ArgumentError, "Use three finite values, for example 1, 2, 3" unless values.length == 3 && values.all?(&:finite?)
          attribute = { "move" => "location", "rotate" => "rotation", "scale" => "scale" }.fetch(match[1].downcase)
          return ["transform", { "object_id" => object.id, "attributes" => { attribute => values } }]
        end
        raise ArgumentError, "No executable Studio procedure matches this direction. Nevaeh will escalate the unsupported request."
      end
    end
  end
end
