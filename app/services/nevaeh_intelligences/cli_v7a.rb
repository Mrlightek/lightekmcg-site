# frozen_string_literal: true
require "json"
require "optparse"
require "stringio"
require_relative "yaml_capability_registry_v7a"
require_relative "capability_reconciler_v7a"
require_relative "trusted_service_catalog_v7a"

module NevaehIntelligences
  # A non-mutating, host-safe CLI entrypoint. Future commands must reuse
  # authorized application services instead of implementing policy in the CLI.
  module CliV7a
    VERSION = "7A.8A.1"
    class UsageError < StandardError; end
    module_function

    def commands
      {
        "help" => "Display commands and usage",
        "version" => "Display CLI version",
        "doctor" => "Inspect CLI installation without booting Rails",
        "capabilities" => "Show CLI operation availability (no capability execution)",
        "config" => "Manage disabled YAML capability definitions (see docs/nevaeh_yaml_capabilities.md)"
      }.freeze
    end

def config_command(args, format:, out:, err:, root: nil)
  raise UsageError, "configuration disabled in production" if ENV["RAILS_ENV"] == "production" || ENV["RACK_ENV"] == "production"
  root ||= File.expand_path("../../..", __dir__)
  op = args.shift
  reg = NevaehIntelligences::YamlCapabilityRegistryV7a
  write = args.delete("--write") ? true : false
  after = []
  if (index = args.index("--after"))
    raise UsageError, "--after requires an identifier" unless args[index + 1]
    after = args[index + 1].split(",")
    args.slice!(index, 2)
  end
  data = case op
         when "list"
           raise UsageError, "unexpected arguments" unless args.empty? && !write && after.empty?
           reg.list(root: root)
         when "create"
           raise UsageError, "usage: config create KEY [--write]" unless args.length == 1 && after.empty?
           reg.create(root: root, key: args.first, write: write)
         when "show", "validate"
           raise UsageError, "usage: config #{op} KEY" unless args.length == 1 && !write && after.empty?
           reg.read(root: root, key: args.first)
         when "services"
           raise UsageError, "usage: config services" unless args.empty? && !write && after.empty?
           NevaehIntelligences::TrustedServiceCatalogV7a.inspect(root: root)
         when "reconcile"
           raise UsageError, "usage: config reconcile KEY" unless args.length == 1 && !write && after.empty?
           NevaehIntelligences::CapabilityReconcilerV7a.plan(root: root, key: args.first, service_paths: (File.file?(File.join(root, "config/nevaeh/trusted_services.yml")) ? NevaehIntelligences::TrustedServiceCatalogV7a.paths(root: root) : {}))
         when "job-add"
           raise UsageError, "usage: config job-add KEY ID SERVICE [--after ID] [--write]" unless args.length == 3
           reg.add_job(root: root, key: args[0], id: args[1], service: args[2], after: after, write: write)
         else
           raise UsageError, "unknown config command"
         end
  if format == "json"
    out.puts JSON.generate({ "ok" => true, "command" => "config #{op}", "wrote" => write, "result" => data })
  else
    out.puts "Nevaeh config #{op} (#{write ? 'written' : 'read-only / preview'}):"
    out.puts(op == "list" ? JSON.pretty_generate(data) : YAML.dump(data))
  end
  0
rescue NevaehIntelligences::TrustedServiceCatalogV7a::Invalid, NevaehIntelligences::CapabilityReconcilerV7a::Invalid, NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, UsageError => e
  err.puts(format == "json" ? JSON.generate({ "ok" => false, "error" => "config_error", "message" => e.message }) : "Nevaeh config error: #{e.message}")
  2
end

    def run(argv, out: $stdout, err: $stderr, root: nil)
      args = Array(argv).dup
      format = "text"
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/nevaeh [--format text|json] <help|version|doctor|capabilities>"
        opts.on("--format FORMAT", %w[text json], "Output format") { |value| format = value }
        opts.on("-h", "--help", "Print usage") { args = ["help"] }
      end
      parser.order!(args)
      command = args.shift || "help"
      raise UsageError, "unknown command" unless commands.key?(command)
      return config_command(args, format: format, out: out, err: err, root: root) if command == "config"
      raise UsageError, "unexpected arguments" unless args.empty?
      result = case command
               when "help" then { "commands" => commands, "usage" => parser.banner }
               when "version" then { "version" => VERSION }
               when "doctor"
                 { "version" => VERSION, "status" => "cli_available", "rails_loaded" => false,
                   "dispatch_enabled" => false, "production_execution_enabled" => false }
               when "capabilities"
                 { "status" => "read_only_cli_registry", "available_commands" => commands.keys,
                   "capability_execution_supported" => false }
               end
      if format == "json"
        out.puts JSON.generate({ "ok" => true, "command" => command, "result" => result })
      else
        case command
        when "help"
          out.puts result.fetch("usage")
          commands.each { |key, desc| out.puts "  #{key.ljust(14)} #{desc}" }
          out.puts "  --format json   Machine-readable output"
        when "version" then out.puts "Nevaeh CLI #{VERSION}"
        when "doctor" then out.puts "Nevaeh CLI #{VERSION}: available (no Rails boot, no dispatch)"
        when "capabilities" then out.puts "CLI commands: #{commands.keys.join(', ')} (capability execution unavailable)"
        end
      end
      0
    rescue OptionParser::ParseError, UsageError => e
      if format == "json"
        err.puts JSON.generate({ "ok" => false, "error" => "usage_error", "message" => e.message })
      else
        err.puts "Nevaeh CLI error: #{e.message}. Try bin/nevaeh help"
      end
      2
    end
  end
end
