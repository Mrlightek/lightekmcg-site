# frozen_string_literal: true

module Marlon
  module Blueprint
    class Compiler
      def initialize(project_type:, selected_pack_keys: [], selected_feature_keys: [])
        @project_type = project_type
        @selected_pack_keys = Array(selected_pack_keys).map(&:to_s)
        @selected_feature_keys = Array(selected_feature_keys).map(&:to_s)
      end

      def call
        packs = selected_packs
        resolved_packs = Resolver.new(packs).resolve
        features = resolved_packs.flat_map(&:features).uniq(&:id)
        features.select! { |feature| @selected_feature_keys.include?(feature.key) } if @selected_feature_keys.any?

        {
          project_type: serialize_project_type,
          capability_packs: resolved_packs.map { |pack| serialize_pack(pack) },
          features: features.map { |feature| serialize_feature(feature) },
          concerns: features.flat_map(&:blueprint_concerns).select(&:active?).map { |concern| serialize_concern(concern) }
        }
      end

      private

      def selected_packs
        base = @project_type.capability_packs.active
        return base if @selected_pack_keys.empty?

        selected = Marlon::CapabilityPack.active.where(key: @selected_pack_keys)
        missing = @selected_pack_keys - selected.pluck(:key)
        raise ArgumentError, "Unknown capability packs: #{missing.join(', ')}" if missing.any?
        selected
      end

      def serialize_project_type
        @project_type.slice(:key, :name, :description, :metadata)
      end

      def serialize_pack(pack)
        pack.slice(:key, :name, :description, :metadata)
      end

      def serialize_feature(feature)
        feature.slice(:key, :name, :description, :metadata)
      end

      def serialize_concern(concern)
        concern.slice(:key, :name, :target_type, :implementation_class, :description, :configuration)
          .merge(feature_key: concern.feature.key)
      end
    end
  end
end
