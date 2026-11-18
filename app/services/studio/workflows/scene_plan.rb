# frozen_string_literal: true
module Studio
  module Workflows
    # A deliberately small, auditable prompt language. Unsupported requests fail
    # instead of silently becoming a rotating cube or executable Python.
    module ScenePlan
      EXAMPLE = "A cube spins under soft lighting viewed from front"
      PATTERN = /\A(?:a |an )?(cube|sphere|cylinder) (spins|rotates|slides|stays still)(?: under (soft|bright|low) (?:light|lights|lighting))?(?: viewed from (?:the )?(front|angle|overhead))?\z/i
      def self.parse(prompt)
        text=prompt.to_s.strip.delete_suffix(".")
        match=PATTERN.match(text)
        raise ArgumentError,"This workflow supports a cube, sphere or cylinder with spin, slide or still motion. Try: #{EXAMPLE}." unless match && text.length<=300
        {"scene_preset"=>match[1].downcase,"procedural_script_params"=>{
          "motion"=>{"spins"=>"spin","rotates"=>"spin","slides"=>"slide","stays still"=>"still"}.fetch(match[2].downcase),
          "lighting"=>(match[3] || "soft").downcase,"camera"=>(match[4] || "angle").downcase}}
      end
    end
  end
end
