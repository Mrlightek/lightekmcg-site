# frozen_string_literal: true
require "json"
require "optparse"
module NevaehIntelligences
  module ReviewPacketCommandV7a
    module_function
    def run(args, out: $stdout, err: $stderr)
      arguments = args.dup
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/nevaeh review-packet /tmp/nevaeh-reviewed-... (read-only)"
        opts.on("--help") { out.puts(opts); return 0 }
      end
      parser.parse!(arguments)
      raise ArgumentError, "exactly one bundle directory required" unless arguments.size == 1
      require_relative "../../../config/environment"
      out.puts JSON.pretty_generate(AcceptanceReviewPacketV7a.build(destination: arguments.fetch(0)))
      0
    rescue OptionParser::ParseError, ArgumentError, AcceptanceReviewPacketV7a::Rejected => e
      err.puts "review-packet refused: #{e.message}"
      1
    end
  end
end
