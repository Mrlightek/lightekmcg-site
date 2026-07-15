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
