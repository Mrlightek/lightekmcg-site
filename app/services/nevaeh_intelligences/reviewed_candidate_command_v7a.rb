# frozen_string_literal: true
require "json"
require "optparse"
module NevaehIntelligences
  module ReviewedCandidateCommandV7a
    module_function
    def run(arguments, out: $stdout, err: $stderr)
      args = arguments.dup
      write = false
      destination = nil
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/nevaeh reviewed-candidate TICKET_ID CAPABILITY_KEY [--write --destination ABSOLUTE_NEW_DIRECTORY]"
        opts.on("--write") { write = true }
        opts.on("--destination PATH") { |value| destination = value }
        opts.on("--help") { out.puts(opts); return 0 }
      end
      parser.parse!(args)
      raise ArgumentError, "ticket ID and capability key required" unless args.size == 2 && /\A[1-9][0-9]*\z/.match?(args.first)
      raise ArgumentError, "destination requires --write" if destination && !write
      raise ArgumentError, "--write requires --destination" if write && destination.nil?
      require_relative "../../../config/environment"
      raise ArgumentError, "ticket drafts disabled" unless TicketDraftAccessV7a.allowed?
      ticket = Marlon::Ticket.find(Integer(args.first))
      result = write ? ReviewedCandidatePipelineV7a.generate(ticket: ticket, key: args.last, destination: destination) : ReviewedCandidatePipelineV7a.preview(ticket: ticket, key: args.last)
      out.puts JSON.pretty_generate(result)
      0
    rescue OptionParser::ParseError, ArgumentError, ActiveRecord::RecordNotFound, ReviewedCandidatePipelineV7a::Rejected,
           ReviewedImplementationTemplateV7a::Rejected, TicketCapabilityDraftBridgeV7a::Rejected, CapabilityCodeGeneratorV7a::Invalid => e
      err.puts "reviewed-candidate refused: #{e.message}"
      1
    end
  end
end
