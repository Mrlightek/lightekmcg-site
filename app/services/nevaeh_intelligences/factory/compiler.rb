# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'rbconfig'
module NevaehIntelligences
  module Factory
    module Compiler
      module_function
      def artifacts(release_id:, definition:, tests:)
        Contract.validate!(definition, tests)
        # All user data is serialized as a dumped Ruby string. No source or class
        # names come from prose, model output, editorial notes or service labels.
        literal = CanonicalJSON.dump(definition).dump
        namespace = "R#{Integer(release_id)}"
        service = "# frozen_string_literal: true\nrequire 'json'\nmodule NevaehConstructed\n  module #{namespace}\n    class Service\n      DEFINITION = JSON.parse(#{literal}).freeze\n      def self.call(inputs:)\n        NevaehIntelligences::Factory::Runtime.call(definition: DEFINITION, inputs: inputs)\n      end\n    end\n  end\nend\n"
        worker = "# frozen_string_literal: true\nmodule NevaehConstructed\n  module #{namespace}\n    class Worker\n      def self.perform(action, payload = {})\n        NevaehIntelligences::FactoryWorker.perform(action, payload.merge('release_id' => #{Integer(release_id)}))\n      end\n    end\n  end\nend\n"
        verifier = "# frozen_string_literal: true\nmodule NevaehConstructed\n  module #{namespace}\n    class Verifier\n      def self.verify!(inputs:, output:)\n        expected = Service.call(inputs: inputs)\n        raise ArgumentError, 'Construction acceptance mismatch' unless output == expected\n        true\n      end\n    end\n  end\nend\n"
        cases = CanonicalJSON.dump(tests).dump
        test_source = "# frozen_string_literal: true\nrequire 'json'\nrequire 'minitest/autorun'\nrequire_relative 'service'\nclass Construction#{namespace}Test < Minitest::Test\n  def test_saved_examples\n    JSON.parse(#{cases}).each { |row| assert_equal row.fetch('expected'), NevaehConstructed::#{namespace}::Service.call(inputs: row.fetch('inputs')) }\n  end\nend\n"
        {'service.rb' => service, 'worker.rb' => worker, 'verifier.rb' => verifier, 'service_test.rb' => test_source}
      end
      def build!(construction:, actor:)
        raise ArgumentError, 'Construction administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehConstruction)
        construction.with_lock do
          Contract.validate!(construction.definition, construction.sample_tests)
          release = construction.releases.create!(version: construction.releases.maximum(:version).to_i + 1,
            definition: construction.definition, sample_tests: construction.sample_tests, fingerprint: Digest::SHA256.hexdigest(CanonicalJSON.dump([construction.definition, construction.sample_tests])))
          source = artifacts(release_id: release.id, definition: release.definition, tests: release.sample_tests)
          # Persist the immutable source on initial insert, not an editable upload.
          release.update_columns(artifacts: source)
          verify!(release)
          release
        end
      end
      def load!(release)
        raise ArgumentError, 'Construction fingerprint mismatch' unless release.fingerprint == Digest::SHA256.hexdigest(CanonicalJSON.dump([release.definition, release.sample_tests]))
        expected = artifacts(release_id: release.id, definition: release.definition, tests: release.sample_tests)
        raise ArgumentError, 'Generated artifacts do not match the saved contract' unless expected == release.artifacts
        @mutex ||= Mutex.new
        @mutex.synchronize do
          namespace = "R#{release.id}"
          unless defined?(NevaehConstructed) && NevaehConstructed.const_defined?(namespace, false)
            Dir.mktmpdir('nevaeh-compiled-') do |directory|
              %w[service.rb verifier.rb worker.rb].each do |file|
                location = File.join(directory, file)
                File.write(location, expected.fetch(file), mode: 'w', perm: 0o600)
                load location
              end
            end
          end
          loaded = NevaehConstructed.const_get(namespace, false)
          raise ArgumentError, 'Loaded construction revision mismatch' unless loaded::Service::DEFINITION == release.definition
          loaded
        end
      end
      def verify!(release)
        implementation = load!(release)
        samples = release.sample_tests.map do |row|
          output = implementation::Service.call(inputs: row.fetch('inputs'))
          raise ArgumentError, 'Sample test failed: output differs from expected' unless output == row.fetch('expected')
          implementation::Verifier.verify!(inputs: row.fetch('inputs'), output: output)
          {inputs: row.fetch('inputs'), expected: row.fetch('expected'), passed: true}
        end
        release.update!(status: 'verified', verification: {samples: samples, artifact_hashes: release.artifacts.transform_values { |source| Digest::SHA256.hexdigest(source) }, verified_at: Time.current.iso8601})
      rescue ArgumentError => error
        release.update!(status: 'failed', verification: {error: error.message})
      end
      def activate!(release:, actor:)
        raise ArgumentError, 'Construction administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehConstruction)
        release.nevaeh_construction.with_lock do
          raise ArgumentError, 'Run and pass verification before activation' unless release.reload.status.in?(%w[verified active])
          load!(release)
          construction = release.nevaeh_construction
          cap = NevaehCapability.find_or_initialize_by(slug: construction.capability_key)
          if cap.persisted? && cap.metadata.to_h['construction_id'] != construction.id
            raise ArgumentError, 'Capability key already belongs to another implementation'
          end
          cap.assign_attributes(name: construction.name, description: construction.description, domain: 'factory', intent_name: construction.capability_key.tr('.', '_'),
            handler: 'NevaehIntelligences::FactoryWorker', queue: 'default', priority: 5, subject_type: 'Marlon::Ticket', gatekeeper_capability: construction.capability_key,
            event_types: ["#{construction.capability_key}.requested"], enabled: true, metadata: {'construction_id' => construction.id, 'release_id' => release.id})
          cap.save!
          intelligence = NevaehIntelligence.find_or_initialize_by(intent_key: construction.capability_key)
          intelligence.assign_attributes(name: construction.name, nevaeh_capability: cap, target_model: 'Marlon::Ticket', operation: 'execute', status: 'published', execution_mode: 'async', instructions: {'action' => 'execute'})
          intelligence.save!
          Gatekeeper::LessonService.record!(key: "nevaeh-construction-#{construction.key}-v#{release.version}",
            title: "Constructed service: #{construction.name}", capability: construction.capability_key,
            symptom: construction.description.presence || construction.name, cause: 'Verified factory construction',
            remediation: CanonicalJSON.dump(release.definition), verification: CanonicalJSON.dump(release.verification),
            metadata: {'nevaeh_capability' => construction.capability_key, 'construction_id' => construction.id, 'release_id' => release.id, 'fingerprint' => release.fingerprint, 'auto_executable' => false})
          construction.update!(active_release: release, status: 'active')
          release.update!(status: 'active')
        end
      end
    end
  end
end
