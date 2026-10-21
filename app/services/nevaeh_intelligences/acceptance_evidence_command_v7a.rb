# frozen_string_literal: true
require "json"
require "optparse"
module NevaehIntelligences
  module AcceptanceEvidenceCommandV7a
    module_function
    def run(args, out: $stdout, err: $stderr)
      arguments = args.dup
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/nevaeh acceptance-evidence /tmp/nevaeh-reviewed-... (read-only)"
        opts.on("--help") { out.puts(opts); return 0 }
      end
      parser.parse!(arguments)
      raise ArgumentError, "exactly one bundle directory required" unless arguments.length == 1
      require_relative "../../../config/environment"
      out.puts JSON.pretty_generate(AcceptanceEvidenceV7a.inspect_bundle(destination: arguments.fetch(0)))
      0
    rescue OptionParser::ParseError, ArgumentError, AcceptanceEvidenceV7a::Rejected => e
      err.puts "acceptance-evidence refused: #{e.message}"
      1
    end
  end
end
