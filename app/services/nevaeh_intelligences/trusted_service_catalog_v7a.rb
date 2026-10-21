# frozen_string_literal: true
require "yaml"
require "pathname"
require "digest"
module NevaehIntelligences
  module TrustedServiceCatalogV7a
    class Invalid < StandardError; end
    ID = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    PATH = %r{\Aapp/services/[a-z0-9_]+(?:/[a-z0-9_]+)*\.rb\z}
    module_function

    def load_catalog(root:)
      root = File.realpath(root)
      location = File.join(root, "config/nevaeh/trusted_services.yml")
      raise Invalid, "trusted service catalog missing" unless File.file?(location) && !File.symlink?(location)
      value = YAML.safe_load(File.read(location), permitted_classes: [], permitted_symbols: [], aliases: false)
      raise Invalid, "unsupported catalog schema" unless value.is_a?(Hash) && value.keys.sort == %w[schema_version services] && value["schema_version"] == 1
      entries = value.fetch("services")
      raise Invalid, "invalid service entries" unless entries.is_a?(Hash) && entries.size <= 500
      entries.each do |id, record|
        raise Invalid, "invalid service id" unless id.is_a?(String) && ID.match?(id)
        raise Invalid, "invalid registration" unless record.is_a?(Hash) && record.keys.sort == %w[path status]
        rel = record.fetch("path")
        raise Invalid, "unsafe registered path" unless rel.is_a?(String) && PATH.match?(rel)
        raise Invalid, "invalid status" unless record["status"] == "review_required" || record["status"] == "reviewed"
        cursor = root
        rel.split("/").each do |part|
          cursor = File.join(cursor, part)
          raise Invalid, "symlink in registered path" if File.symlink?(cursor)
        end
        if File.exist?(cursor)
          raise Invalid, "registered path must be a file" unless File.file?(cursor)
          raise Invalid, "registered path escapes repository" unless File.realpath(cursor).start_with?(root + File::SEPARATOR)
        end
      end
      entries
    rescue Psych::Exception => e
      raise Invalid, "invalid catalog YAML: #{e.class}"
    end

    def inspect(root:)
      root = File.realpath(root)
      load_catalog(root: root).sort.map do |id, entry|
        path = File.join(root, entry.fetch("path"))
        present = File.file?(path)
        { "service" => id, "path" => entry.fetch("path"), "review" => entry.fetch("status"),
          "state" => present ? "present" : "missing", "sha256" => present ? Digest::SHA256.file(path).hexdigest : nil,
          "executable" => false }
      end
    end

    def paths(root:)
      load_catalog(root: root).transform_values { |entry| entry.fetch("path") }
    end
  end
end
