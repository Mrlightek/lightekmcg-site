# frozen_string_literal: true
require 'json'
require 'digest'
require 'ripper'
require 'fileutils'

module NevaehIntelligences
  # Bounded repository-aware authoring, NOT general AI reasoning.
  # Change specification must be supplied explicitly and reviewed.
  module Studio203RepositoryAwareAuthoringV7a
    class Rejected < StandardError; end
    module_function
    TRACKING_KEY = 'STUDIO-203'
    TARGET = 'app/services/studio/capabilities/ticket_snapshot_filter.rb'
    SOURCES = %w[app/services/studio/capabilities/discovery.rb app/services/studio/capabilities/rails_read_adapter.rb].freeze
    ALLOWED_KEYS = %w[require_published include_disabled].freeze

    def preview(ticket:, changes:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a)
      ensure_test!
      plan = planner.from_ticket(ticket: ticket)
      raise Rejected, 'invalid ticket identity' unless ticket.respond_to?(:persisted?) && ticket.persisted? && plan.is_a?(Hash) && plan['ticket_id'] == ticket.id && plan['tracking_key'] == TRACKING_KEY
      raise Rejected, 'unsafe plan' unless plan['status'] == 'planning_only' && plan['execution_enabled'] == false && plan.dig('gatekeeper', 'production_execution_allowed') == false && plan.dig('gatekeeper', 'human_release_approval_required') == true
      raise Rejected, 'plan fingerprint missing' unless plan['fingerprint'].to_s.match?(/\A[0-9a-f]{64}\z/)
      spec = normalize_changes(changes)
      real = File.realpath(root)
      raise Rejected, 'root must be actual Rails checkout' unless real == File.realpath(Rails.root.to_s)
      raise Rejected, 'target collision' if File.exist?(File.join(real, TARGET)) || File.symlink?(File.join(real, TARGET))
      sources = SOURCES.to_h do |path|
        full = File.join(real, path)
        raise Rejected, 'missing source contract' unless File.file?(full) && !File.symlink?(full)
        bytes = File.binread(full)
        raise Rejected, 'source contract invalid Ruby' unless Ripper.sexp(bytes)
        [path, Digest::SHA256.hexdigest(bytes)]
      end
      body = synthesize(spec)
      raise Rejected, 'generated Ruby invalid' unless Ripper.sexp(body)
      {'ticket_id' => ticket.id, 'tracking_key' => TRACKING_KEY,
       'plan_fingerprint' => plan['fingerprint'], 'reference_sha256' => sources,
       'change_specification' => spec, 'target_path' => TARGET,
       'source_sha256' => Digest::SHA256.hexdigest(body),
       'code_authoring_mode' => 'bounded_rule_composition', 'execution_authorized' => false,
       'tests_executed' => false, 'human_review_required' => true, 'autonomous_ai_authoring' => false}
    end

    def generate(ticket:, changes:, destination:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a)
      report = preview(ticket: ticket, changes: changes, root: root, planner: planner)
      checkout = File.realpath(root)
      dest = File.expand_path(destination)
      parent = File.dirname(dest)
      raise Rejected, 'output exists' if File.exist?(dest) || File.symlink?(dest)
      raise Rejected, 'unsafe output parent' unless File.directory?(parent) && !File.symlink?(parent)
      actual_parent = File.realpath(parent)
      raise Rejected, 'output inside checkout' if actual_parent == checkout || actual_parent.start_with?(checkout + File::SEPARATOR)
      body = synthesize(report.fetch('change_specification'))
      created = false
      begin
        Dir.mkdir(dest, 0700)
        created = true
        write_exclusive(File.join(dest, 'ticket_snapshot_filter.rb'), body)
        write_exclusive(File.join(dest, 'provenance.json'), JSON.pretty_generate(report) + "\n")
        patch = "--- /dev/null\n+++ b/#{TARGET}\n@@ -0,0 +1,#{body.lines.length} @@\n" + body.lines.map { |l| "+#{l}" }.join
        write_exclusive(File.join(dest, 'review.patch'), patch)
        report.merge('destination' => dest)
      rescue StandardError
        FileUtils.remove_entry_secure(dest) if created && File.directory?(dest) && !File.symlink?(dest)
        raise
      end
    end

    def normalize_changes(raw)
      raise Rejected, 'explicit changes object required' unless raw.is_a?(Hash) && raw.keys.all? { |k| k.is_a?(String) }
      raise Rejected, 'unknown change rule' unless (raw.keys - ALLOWED_KEYS).empty? && (ALLOWED_KEYS - raw.keys).empty?
      raise Rejected, 'rules must be booleans' unless raw.values.all? { |v| v == true || v == false }
      ALLOWED_KEYS.to_h { |key| [key, raw.fetch(key)] }
    end

    def synthesize(spec)
      # Composes behavior from individual validated requirements; not a fixed full-source template.
      conditions = []
      conditions << "next unless row['published'] == true" if spec.fetch('require_published')
      conditions << "next unless row['enabled'] == true" unless spec.fetch('include_disabled')
      conditional_lines = conditions.map { |line| "          #{line}\n" }.join
      <<~RUBY
        # frozen_string_literal: true
        # Ticket-driven bounded rule composition for STUDIO-203; review required.
        module Studio
          module Capabilities
            module TicketSnapshotFilter
              class Invalid < StandardError; end
              module_function
              def call(entries:)
                raise Invalid, 'entries must be array' unless entries.is_a?(Array) && entries.length <= 1000
                seen = {}
                rows = entries.filter_map do |row|
                  raise Invalid, 'invalid record' unless row.is_a?(Hash) && row.keys.all? { |k| k.is_a?(String) }
                  name = row['key'] || row['slug']
                  raise Invalid, 'invalid identifier' unless name.is_a?(String) && name.match?(/\\A[a-z][a-z0-9_.-]*\\z/) && name.length <= 100
                  raise Invalid, 'duplicate identifier' if seen[name]
                  seen[name] = true
                  %w[enabled published].each do |flag|
                    raise Invalid, 'invalid boolean' if row.key?(flag) && ![true, false].include?(row[flag])
                  end
        #{conditional_lines}          {'key' => name, 'enabled' => row['enabled'] == true, 'published' => row['published'] == true, 'execution_authorized' => false}
                end
                rows.sort_by { |row| row.fetch('key') }
              end
            end
          end
        end
      RUBY
    end

    def write_exclusive(path, content)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(content) }
    end

    def ensure_test!
      raise Rejected, 'test only' unless Rails.env.test?
      raise Rejected, 'wrong database' unless ActiveRecord::Base.connection_db_config.database == 'lightekmcg_site_test'
    end
  end
end
