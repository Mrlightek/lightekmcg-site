# frozen_string_literal: true
module Marlon
  # THE STUDIO'S BUILD CATALOG — as data.
  #
  # ProjectType -> CapabilityPack -> Feature -> BlueprintConcern lives in the DB,
  # so "what the Studio can build" is editable at runtime (eventually through the
  # dashboard) rather than hardcoded. This module is the read surface.
  #
  # Everything is guarded: if the meta-framework isn't installed, these return
  # empty rather than raising. Doctrine: dynamic reads, capability detection.
  module Catalog
    module_function

    def available?
      defined?(Marlon::ProjectType) ? true : false
    end

    # Every project type the Studio can build (dynamic collection).
    def project_types
      return [] unless available?
      Marlon::ProjectType.active.order(:name).to_a
    rescue StandardError
      []
    end

    def project_type(key)
      return nil unless available?
      Marlon::ProjectType.active.find_by(key: key.to_s)
    rescue StandardError
      nil
    end

    def capability_packs
      return [] unless defined?(Marlon::CapabilityPack)
      Marlon::CapabilityPack.active.order(:name).to_a
    rescue StandardError
      []
    end

    # What a project type will ACTUALLY generate — packs with their dependencies
    # resolved (the Resolver handles transitive deps + cycle detection), and the
    # full feature set those packs carry.
    def preview(key)
      t = project_type(key)
      return nil unless t

      packs    = t.resolved_capability_packs
      features = packs.flat_map(&:features).uniq(&:id)
      {
        project_type: t,
        packs: packs,
        features: features,
        pack_keys: packs.map(&:key),
        feature_keys: features.map(&:key),
        concern_count: features.sum { |f| f.blueprint_concerns.size }
      }
    rescue StandardError => e
      { project_type: nil, error: e.message, packs: [], features: [] }
    end

    # Summary for a dashboard list: one row per project type.
    def index
      project_types.map do |t|
        packs = begin
          t.resolved_capability_packs
        rescue StandardError
          []
        end
        {
          key: t.key, name: t.name,
          description: (t.respond_to?(:description) ? t.description : nil),
          pack_count: packs.size,
          feature_count: packs.flat_map(&:features).uniq(&:id).size
        }
      end
    end
  end
end
