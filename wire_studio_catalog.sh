#!/usr/bin/env bash
# D — wire the meta-framework as the Studio's BUILD CATALOG.
#
#   Marlon::Catalog      -> reads the DB catalog (ProjectTypes, packs, resolved preview)
#   Marlon::BuildHandler -> dispatch handler; runs `rails g marlon:meta_framework`
#   Marlon::Builder      -> submits a build to dispatch (builds queue, RTM-visible)
#
# The catalog is DATA: add a ProjectType row and the Studio can build it. No code
# change. Everything guarded — if the meta-framework isn't installed, these
# degrade instead of raising.
#
# PREREQ: install_marlon_meta_framework.sh has been run (Marlon::ProjectType exists).
#   cd ~/Desktop/Development/lightekmcg-site && bash wire_studio_catalog.sh
set -uo pipefail
echo "==> Wiring the Studio build catalog ($(pwd))"
[ -f "config/application.rb" ] || { echo "  error: run from the Rails app root" >&2; exit 1; }

mkdir -p app/services/marlon

# ---------------- Catalog: the reads ----------------
cat > app/services/marlon/catalog.rb <<'RUBY'
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
RUBY
echo "  [1/3] Marlon::Catalog — the catalog reads (guarded)"

# ---------------- BuildHandler: the dispatch contract ----------------
cat > app/services/marlon/build_handler.rb <<'RUBY'
# frozen_string_literal: true
require "open3"

module Marlon
  # dymond_dispatch handler contract: .perform(*args) -> Hash.
  #
  # Runs the meta-framework generator, which materializes the resolved capability
  # concerns/services/jobs/policies onto a model. Runs on a dispatch worker, so
  # the build shows on the RTM wallboard (builds queue) with its output recorded
  # on the WorkItem.
  module BuildHandler
    module_function

    def perform(spec = {})
      s     = normalize(spec)
      type  = s["project_type"].to_s
      model = s["model"].to_s
      packs = Array(s["packs"]).map(&:to_s).reject(&:empty?)

      raise "project_type required" if type.empty?
      raise "model required"        if model.empty?
      raise "unknown project type '#{type}'" unless Marlon::Catalog.project_type(type)

      cmd = ["bin/rails", "g", "marlon:meta_framework", type, model]
      # Thor array option: --packs a b c
      cmd += (["--packs"] + packs) if packs.any?
      cmd << "--force" if s["force"]

      out, err, status = Open3.capture3({ "RAILS_ENV" => Rails.env }, *cmd, chdir: Rails.root.to_s)
      unless status.success?
        raise "generator failed (#{status.exitstatus}): #{err.lines.last(5).join}"
      end

      {
        project_type: type,
        model: model,
        packs: packs,
        command: cmd.join(" "),
        output: out.lines.last(40).join
      }
    end

    def normalize(spec)
      if spec.respond_to?(:with_indifferent_access)
        spec.with_indifferent_access
      elsif spec.is_a?(Hash)
        spec.transform_keys(&:to_s)
      else
        {}
      end
    end
  end
end
RUBY
echo "  [2/3] Marlon::BuildHandler — runs the generator on a worker"

# ---------------- Builder: submit a build ----------------
cat > app/services/marlon/builder.rb <<'RUBY'
# frozen_string_literal: true
module Marlon
  # Submit a capability build. Routes through dispatch when installed (builds
  # queue, wallboard-visible, completion dispositions); runs inline otherwise.
  #
  #   Marlon::Builder.build!(project_type: "managed_it_services", model: "Device")
  #   Marlon::Builder.build!(project_type: "saas", model: "Account", packs: %w[billing crm])
  module Builder
    module_function

    def build!(project_type:, model:, packs: [], force: false)
      spec = {
        "project_type" => project_type.to_s,
        "model"        => model.to_s,
        "packs"        => Array(packs).map(&:to_s),
        "force"        => !!force
      }

      if defined?(DymondDispatch::Dispatcher)
        DymondDispatch::Dispatcher.submit(
          "Marlon::BuildHandler",
          args: [spec], queue: "builds", priority: 3,
          dispositions: [
            { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
          ]
        )
      else
        Marlon::BuildHandler.perform(spec)
      end
    end

    # Validate before submitting — cheap feedback for a UI.
    def validate(project_type:, model:)
      errors = []
      errors << "project_type required" if project_type.to_s.strip.empty?
      errors << "model required"        if model.to_s.strip.empty?
      unless model.to_s.strip.empty? || model.to_s.match?(/\A[A-Z][A-Za-z0-9:]*\z/)
        errors << "model must be a Ruby class name (e.g. Device, Billing::Invoice)"
      end
      if project_type.to_s.present? && Marlon::Catalog.project_type(project_type).nil?
        errors << "unknown project type '#{project_type}'"
      end
      errors
    end
  end
end
RUBY
echo "  [3/3] Marlon::Builder — submits to dispatch (builds queue)"

echo ""
echo "==> Verify:"
echo "    ruby -c app/services/marlon/catalog.rb"
echo "    ruby -c app/services/marlon/build_handler.rb"
echo "    ruby -c app/services/marlon/builder.rb"
echo ""
echo "==> Then (restart first):"
cat <<'EX'
    # the catalog is data:
    bin/rails runner 'pp Marlon::Catalog.index'

    # what a type actually generates (deps resolved):
    bin/rails runner 'pp Marlon::Catalog.preview("managed_it_services").slice(:pack_keys, :feature_keys, :concern_count)'

    # BUILD IT — routes through dispatch, watch /dashboard/dispatch
    bin/rails runner 'p Marlon::Builder.build!(project_type: "managed_it_services", model: "Device")'
EX
echo ""
echo "==> The build appears on the RTM wallboard: builds queue, Marlon::BuildHandler."
echo "   That's the Studio's catalog + the work layer + the generator, one flow."
