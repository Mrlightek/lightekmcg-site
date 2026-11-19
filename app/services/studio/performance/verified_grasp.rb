# frozen_string_literal: true
module Studio
  module Performance
    class VerifiedGrasp
      KEY="grasp_verified"
      BINDINGS={"profile"=>"contact_biped","version"=>1,"rig"=>"ContactRig","hand"=>"ContactHand"}.freeze
      FILES=%w[grasp_v4.py spatial_checks.py bench_v1.py hand_rig_v1.py hand_surface_v1.py contact_character_v1.py profiles/contact_biped_v1.json physics/pickup_v1/run.py physics/pickup_v1/solve.py physics/pickup_v1/feasible.py physics/pickup_v1/planner.py physics/pickup_v1/ik.py physics/pickup_v1/ik_untracked.py physics/pickup_v1/extended.py physics/pickup_v1/clearance_checks.py physics/grasp_v3.py physics/human_v1.json physics/pedestal_contact_v3.json].freeze
      PHASES={"commit"=>[0,0.25],"reach_grip"=>[0.25,1.85],"lift"=>[1.85,3.25],"assess"=>[3.25,4.5],"place_unload"=>[4.5,6.25],"recover"=>[6.25,8]}.freeze
      def self.active?(inputs) = inputs.dig("mechanics","action")=="grasp" && inputs.dig("mechanics","version")==4
      def self.profile = {"id"=>"contact_biped_v1","body_mass_kg"=>75,"prop_mass_kg"=>0.2,"prop_radius_m"=>0.045,"duration_s"=>8,"fps"=>24}
      def self.objects
        rows=Grasp.objects.deep_dup
        rows.each { |row| row["definition"]["location"][0]=0.46;row["definition"]["location"][1]=-0.22 }
        rows.find { |row| row["id"]=="ball" }["definition"]["mechanics_grasp_version"]=4
        rows.find { |row| row["id"]=="grasp_pedestal" }["definition"]["scale"]=[0.08,0.10,0.4275]
        rows.reject! { |row| row["type"]=="camera" }
        rows<<{"id"=>"ground","name"=>"Ground","type"=>"plane","definition"=>{"location"=>[0,0,0],"scale"=>[4,4,1]}}
        [["grasp_wide",[2.9,-4.7,2.15],[0.2,-0.05,0.95],55],["grasp_close",[1.6,-2.2,1.65],[0.35,-0.18,1.12],68],["grasp_recovery",[2.8,2.8,1.95],[0.2,-0.08,0.92],40]].each do |id,location,target,lens|
          rows<<{"id"=>id,"name"=>id.tr('_',' '),"type"=>"camera","definition"=>{"location"=>location,"look_at"=>target,"lens"=>lens}}
        end
        rows
      end
      def self.register(objects,raw)
        raise ArgumentError,"Use the contact_biped v1 rig and weighted hand" unless raw==BINDINGS
        rig=objects.find { |o|o["name"]=="ContactRig" && o.dig("definition","native_type")=="ARMATURE" }
        bones=Array(rig&.dig("definition","bones")).map { |b|b["name"] }
        expected=["Palm","Part.wristR","Part.head",*5.times.flat_map { |f|3.times.map { |j|"Digit.#{f}.#{j}" } }]
        raise ArgumentError,"The reusable hand rig is incomplete" unless (expected-bones).empty? && objects.any? { |o|o["name"]=="ContactHand" && o.dig("definition","native_type")=="MESH" }
        raw.deep_dup
      end
      def self.validate!(inputs,staging)
        raise ArgumentError,"Choose the validated pickup setup and its ball" unless inputs["camera_mode"]=="template" && staging["key"]==KEY && inputs.dig("mechanics","target_id")=="ball"
        raise ArgumentError,"This eight-second action is silent and owns its acting and gaze" if inputs["dialogue"].present? || inputs["audio_asset_id"].present? || inputs["attention"]
        expected=objects.to_h { |o|[o["id"],o] }
        staging.fetch("objects").each do |o|
          source=expected[o["id"]]
          raise ArgumentError,"Use the calibrated pickup set without extra obstacles" unless source && source["type"]==o["type"] && source["definition"]==o["definition"]
        end
        raise ArgumentError,"The calibrated pickup set is incomplete" unless staging["objects"].size==expected.size
      end
      # This instruction selects a reviewed action; it never invents motion/physics parameters.
      def self.from_prompt(payload)
        text=payload["action_prompt"].to_s.strip
        return payload if text.empty?
        raise ArgumentError,"Use: pick up the ball, inspect it, and put it back" unless text.length<=240 && text.match?(/\Apick up (?:the |that )?ball[, ]+(?:and )?(?:inspect|look at) it[, ]+(?:and )?put it (?:back|down)[.!]?\z/i)
        raise ArgumentError,"Choose the validated pickup action" if payload["mechanics"].present? && payload["mechanics"]!={"action"=>"grasp","version"=>4,"target_id"=>"ball"}
        payload.merge("scene_template"=>KEY,"mechanics"=>{"action"=>"grasp","version"=>4,"target_id"=>"ball"},"dialogue"=>"","gesture"=>"still","camera_mode"=>"template")
      end
    end
  end
end
