# frozen_string_literal: true
require 'json'
require 'digest'
require 'ripper'
require 'fileutils'
require 'tmpdir'

module NevaehIntelligences
  # Constrained STUDIO-203 ticket-to-source experiment. NOT general AI authoring.
  # Consumes the trusted development plan but does not dispatch or promote changes.
  module Studio203ConstrainedImplementationV7a
    class Rejected < StandardError; end
    module_function
    TARGET = 'app/services/studio/capabilities/ticket_snapshot_contract.rb'
    TICKET_KEY = 'STUDIO-203'
    GENERATOR = 'studio203_constrained_implementation_v7a'
    SOURCE = <<~'GENERATED_RUBY'.freeze
      # frozen_string_literal: true
      # Generated for STUDIO-203 in a constrained ticket-conditioned synthesis experiment.
      require 'json'
      require 'digest'
      module Studio
        module Capabilities
          module TicketSnapshotContract
            class Invalid < StandardError; end
            MAX_ROWS = 1000
            IDENTIFIER = /\A[a-z][a-z0-9_.-]*\z/
            BLOCKED = %w[secret token password handler queue command credential private_key authorization_policy].freeze
            module_function
            def call(entries:)
              raise Invalid, 'entries must be an array' unless entries.is_a?(Array)
              raise Invalid, 'too many entries' if entries.length > MAX_ROWS
              seen = {}
              rows = entries.map do |entry|
                raise Invalid, 'entry must be a string-keyed hash' unless entry.is_a?(Hash) && entry.keys.all? { |k| k.is_a?(String) }
                raise Invalid, 'implementation details forbidden' unless (entry.keys & BLOCKED).empty?
                name = entry['slug'] || entry['key']
                raise Invalid, 'conflicting identity' if entry.key?('key') && entry.key?('slug') && entry['key'] != entry['slug']
                raise Invalid, 'invalid identity' unless name.is_a?(String) && name.size <= 100 && IDENTIFIER.match?(name)
                raise Invalid, 'duplicate identity' if seen[name]
                seen[name] = true
                %w[enabled published].each do |flag|
                  raise Invalid, 'invalid flag' if entry.key?(flag) && ![true, false].include?(entry[flag])
                end
                {'key' => name, 'enabled' => entry['enabled'] == true, 'published' => entry['published'] == true,
                 'execution_authorized' => false, 'release_approved' => false}
              end
              rows.sort_by! { |entry| entry.fetch('key') }
              {'ticket_key' => 'STUDIO-203', 'capabilities' => rows,
               'fingerprint' => Digest::SHA256.hexdigest(JSON.generate(rows)), 'authorization_granted' => false}
            rescue JSON::GeneratorError, EncodingError => e
              raise Invalid, "invalid encoding: #{e.class}"
            end
          end
        end
      end
    GENERATED_RUBY

    def preview(ticket:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a)
      plan = planner.from_ticket(ticket: ticket)
      check_plan!(ticket: ticket, plan: plan, root: root)
      source = SOURCE.dup
      raise Rejected, 'invalid generated Ruby' unless Ripper.sexp(source)
      {
        'tracking_key' => TICKET_KEY,
        'ticket_id' => ticket.id,
        'development_plan_fingerprint' => plan.fetch('fingerprint'),
        'source_sha256' => Digest::SHA256.hexdigest(source),
        'target_path' => TARGET,
        'generator' => GENERATOR,
        'code_authoring_mode' => 'fixed_allowlisted_template',
        'implementation_verified' => false,
        'authorization_granted' => false,
        'production_allowed' => false
      }.freeze
    rescue KeyError, TypeError, ArgumentError => e
      raise Rejected, "invalid engineering contract: #{e.class}"
    end

    def generate(ticket:, destination:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a)
      preview_info = preview(ticket: ticket, root: root, planner: planner)
      check_destination!(destination: destination, root: root)
      created = false
      begin
        Dir.mkdir(destination, 0700)
        created = true
        candidate = File.join(destination, 'ticket_snapshot_contract.rb')
        File.open(candidate, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(SOURCE) }
        provenance = preview_info.merge(
          'source_sha256' => Digest::SHA256.file(candidate).hexdigest,
          'review_required' => true,
          'tests_executed' => false,
          'is_autonomous_reasoning' => false
        )
        File.open(File.join(destination, 'provenance.json'), File::WRONLY | File::CREAT | File::EXCL, 0600) do |f|
          f.write(JSON.pretty_generate(provenance) + "\n")
        end
        # Patch is deliberately a new-file diff, no repository mutation.
        patch = "--- a/#{TARGET}\n+++ b/#{TARGET}\n@@ -0,0 +1,#{SOURCE.lines.count} @@\n" + SOURCE.lines.map { |line| "+#{line}" }.join
        File.open(File.join(destination, 'review.patch'), File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(patch) }
        provenance.merge('destination' => destination)
      rescue StandardError
        FileUtils.remove_entry_secure(destination) if created && File.directory?(destination) && !File.symlink?(destination)
        raise
      end
    end

    def check_plan!(ticket:, plan:, root:)
      raise Rejected, 'test environment only' unless Rails.env.test?
      raise Rejected, 'ticket must be persisted' unless ticket.respond_to?(:persisted?) && ticket.persisted?
      raise Rejected, 'invalid plan' unless plan.is_a?(Hash)
      raise Rejected, 'wrong ticket' unless plan['ticket_id'] == ticket.id && plan['tracking_key'] == TICKET_KEY
      raise Rejected, 'plan not inert' unless plan['status'] == 'planning_only' && plan['execution_enabled'] == false
      raise Rejected, 'unsafe release policy' unless plan.dig('gatekeeper', 'production_execution_allowed') == false && plan.dig('gatekeeper', 'human_release_approval_required') == true
      raise Rejected, 'plan fingerprint missing' unless plan['fingerprint'].is_a?(String) && plan['fingerprint'].match?(/\A[0-9a-f]{64}\z/)
      base = File.realpath(root)
      raise Rejected, 'application root mismatch' unless base == File.realpath(Rails.root.to_s)
      path = File.join(base, TARGET)
      raise Rejected, 'target already exists' if File.exist?(path) || File.symlink?(path)
      roadmap_path = File.join(base, 'config/project_tracking/lightek_studio.json')
      raise Rejected, 'unsafe roadmap path' unless File.file?(roadmap_path) && !File.symlink?(roadmap_path)
      items = JSON.parse(File.read(roadmap_path)).fetch('items')
      matches = items.select { |i| i['key'] == TICKET_KEY }
      raise Rejected, 'canonical ticket missing or ambiguous' unless matches.length == 1
      raise Rejected, 'unexpected objective' unless matches.first.fetch('title').include?('Capability Registry')
      true
    end

    def check_destination!(destination:, root:)
      raise Rejected, 'invalid destination' unless destination.is_a?(String) && !destination.empty?
      raise Rejected, 'existing destination' if File.exist?(destination) || File.symlink?(destination)
      parent = File.dirname(File.expand_path(destination))
      raise Rejected, 'destination parent missing' unless File.directory?(parent) && !File.symlink?(parent)
      base = File.realpath(root)
      actual = File.realpath(parent)
      raise Rejected, 'destination inside repository' if actual == base || actual.start_with?(base + File::SEPARATOR)
      raise Rejected, 'destination outside temporary area' unless actual.start_with?(File.realpath(Dir.tmpdir) + File::SEPARATOR)
      true
    end
  end
end
