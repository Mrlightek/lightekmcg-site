# frozen_string_literal: true
require "json"
require "optparse"
module NevaehIntelligences
  module GeneratorCommandV7a
    module_function
    def run(argv, out: $stdout, err: $stderr)
      opts = { write: false }
      parser = OptionParser.new do |p|
        p.banner = "Usage: bin/nevaeh draft KEY [--write --destination /absolute/new/path]"
        p.on("--write", "Generate inert draft files into new directory") { opts[:write] = true }
        p.on("--destination DIR", "New isolated output directory") { |v| opts[:destination] = v }
      end
      args = argv.dup
      parser.parse!(args)
      raise ArgumentError, "exactly one capability key required" unless args.length == 1
      raise ArgumentError, "destination requires --write" if opts[:destination] && !opts[:write]
      raise ArgumentError, "--write requires --destination" if opts[:write] && !opts[:destination]
      raise ArgumentError, "absolute destination required" if opts[:write] && !opts[:destination].start_with?(File::SEPARATOR)
      require_relative "../../../config/environment"
      raise ArgumentError, "local test/development only" unless Rails.env.test? || Rails.env.development?
      raise ArgumentError, "write prohibited in production" if Rails.env.production?
      generator = NevaehIntelligences::CapabilityCodeGeneratorV7a
      result = opts[:write] ? generator.generate(root: Rails.root.to_s, key: args.first, destination: opts[:destination]) : generator.plan(root: Rails.root.to_s, key: args.first)
      out.puts(JSON.pretty_generate(result))
      0
    rescue OptionParser::ParseError, ArgumentError, NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid,
           NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid => e
      err.puts "Nevaeh draft rejected: #{e.message}"
      2
    end
  end
end
