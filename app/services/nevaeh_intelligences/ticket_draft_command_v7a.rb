# frozen_string_literal: true
require "json"
require "optparse"
module NevaehIntelligences
  module TicketDraftCommandV7a
    module_function
    def run(arguments, out: $stdout, err: $stderr)
      args = arguments.dup
      write = false
      destination = nil
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/nevaeh ticket-draft TICKET_ID CAPABILITY_KEY [--write --destination ABSOLUTE_NEW_DIRECTORY]"
        opts.on("--write", "Generate isolated inert drafts") { write = true }
        opts.on("--destination PATH", "New output folder outside Rails root") { |v| destination = v }
        opts.on("--help") { out.puts(opts); return 0 }
      end
      parser.parse!(args)
      raise ArgumentError, "ticket ID and capability key required" unless args.length == 2 && /\A[1-9][0-9]*\z/.match?(args[0])
      raise ArgumentError, "destination requires --write" if destination && !write
      raise ArgumentError, "--write requires --destination" if write && !destination
      require_relative "../../../config/environment"
      raise ArgumentError, "ticket drafts disabled outside test or opted-in local development" unless TicketDraftAccessV7a.allowed?
      ticket = Marlon::Ticket.find(Integer(args[0]))
      result = if write
        TicketCapabilityDraftBridgeV7a.generate(ticket: ticket, capability_key: args[1], destination: destination)
      else
        TicketCapabilityDraftBridgeV7a.preview(ticket: ticket, capability_key: args[1])
      end
      out.puts(JSON.pretty_generate(result))
      0
    rescue OptionParser::ParseError, ArgumentError, ActiveRecord::RecordNotFound, TicketCapabilityDraftBridgeV7a::Rejected, CapabilityCodeGeneratorV7a::Invalid => e
      err.puts("ticket-draft refused: #{e.message}")
      1
    end
  end
end
