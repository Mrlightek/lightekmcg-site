# frozen_string_literal: true

require "rails/generators"
require "json"

module Marlon
  module Generators
    # Materializes a database-defined Marlon project blueprint.
    #
    # Examples:
    #   bin/rails g marlon:meta_framework managed_it_services Device
    #   bin/rails g marlon:meta_framework managed_it_services Device --packs mdm,rmm
    #   bin/rails g marlon:meta_framework managed_it_services Device --features remote_lock,remote_wipe
    #   bin/rails g marlon:meta_framework managed_it_services Device --api --policies --force
    class MetaFrameworkGenerator < Rails::Generators::Base
      namespace "marlon:meta_framework"

      argument :project_type_key, type: :string, required: true, banner: "PROJECT_TYPE"
      argument :model_name, type: :string, required: true, banner: "MODEL"

      class_option :packs, type: :array, default: [], desc: "Restrict generation to these packs"
      class_option :features, type: :array, default: [], desc: "Restrict generation to these features"
      class_option :namespace, type: :string, default: "Marlon", desc: "Generated Ruby namespace"
      class_option :api, type: :boolean, default: false, desc: "Generate API controllers"
      class_option :policies, type: :boolean, default: true, desc: "Generate Pundit-style policies"
      class_option :jobs, type: :boolean, default: true, desc: "Generate Active Jobs"
      class_option :force, type: :boolean, default: false, desc: "Overwrite generated files"
      class_option :manifest, type: :boolean, default: true, desc: "Write blueprint JSON manifest"

      def validate!
        project_type
        blueprint
      end

      def generate_blueprint
        blueprint.fetch(:concerns).each do |definition|
          generate_definition(definition.deep_symbolize_keys)
        end
      end

      def write_manifest
        return unless options[:manifest]

        writer.write(
          "config/marlon/blueprints/#{project_type.key}.json",
          JSON.pretty_generate(blueprint),
          blueprint_key: project_type.key,
          artifact_type: "manifest"
        )
      end

      def summary
        say_status :project_type, project_type.name, :green
        say_status :packs, blueprint.fetch(:capability_packs).map { |item| item[:key] || item["key"] }.join(", "), :green
        say_status :features, blueprint.fetch(:features).size.to_s, :green
        say_status :artifacts, blueprint.fetch(:concerns).size.to_s, :green
      end

      private

      def project_type
        @project_type ||= Marlon::ProjectType.active.find_by!(key: project_type_key)
      rescue ActiveRecord::RecordNotFound
        raise Thor::Error, "Unknown project type: #{project_type_key}"
      end

      def blueprint
        @blueprint ||= Marlon::Blueprint::Compiler.new(
          project_type: project_type,
          selected_pack_keys: split_option(:packs),
          selected_feature_keys: split_option(:features)
        ).call.deep_symbolize_keys
      rescue ArgumentError, Marlon::Blueprint::Resolver::CircularDependencyError => e
        raise Thor::Error, e.message
      end

      def split_option(name)
        Array(options[name]).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:blank?)
      end

      def writer
        @writer ||= Marlon::Blueprint::FileWriter.new(force: options[:force])
      end

      def generate_definition(definition)
        feature_key = definition.fetch(:feature_key)
        concern_key = definition.fetch(:key)
        class_name = definition[:implementation_class].presence || concern_key.camelize

        write_model_concern(feature_key, concern_key, class_name)
        write_service(feature_key, concern_key, class_name)
        write_job(feature_key, concern_key, class_name) if options[:jobs]
        write_policy(feature_key, concern_key, class_name) if options[:policies]
        write_api_controller(feature_key, concern_key, class_name) if options[:api]
      end

      def write_model_concern(feature_key, concern_key, class_name)
        body = <<~RUBY
          # frozen_string_literal: true

          module #{root_module}
            module #{class_name}
              extend ActiveSupport::Concern

              def run_#{concern_key}(action:, payload: {})
                #{dispatch_line(class_name)}
              end
            end
          end
        RUBY

        write("app/models/concerns/#{root_path}/#{feature_key}/#{concern_key}.rb", body, "model_concern")
      end

      def write_service(feature_key, concern_key, class_name)
        body = <<~RUBY
          # frozen_string_literal: true

          module #{root_module}
            class #{class_name}Service
              def self.call(record:, action:, payload: {})
                new(record:, action:, payload:).call
              end

              def initialize(record:, action:, payload: {})
                @record = record
                @action = action.to_s
                @payload = payload.to_h.deep_symbolize_keys
              end

              def call
                # Implement #{concern_key.tr('_', ' ')} for #{model_name.camelize}.
                # Use an idempotency key before external side effects.
                # Emit a domain event after a successful state transition.
                Rails.logger.info(
                  capability: "#{feature_key}",
                  concern: "#{concern_key}",
                  action: @action,
                  record: @record.to_global_id.to_s,
                  payload: @payload
                )
              end
            end
          end
        RUBY

        write("app/services/#{root_path}/#{feature_key}/#{concern_key}_service.rb", body, "service")
      end

      def write_job(feature_key, concern_key, class_name)
        body = <<~RUBY
          # frozen_string_literal: true

          module #{root_module}
            class #{class_name}Job < ApplicationJob
              queue_as :default
              retry_on StandardError, wait: :polynomially_longer, attempts: 5
              discard_on ActiveJob::DeserializationError

              def perform(record, action, payload = {})
                #{class_name}Service.call(record:, action:, payload:)
              end
            end
          end
        RUBY

        write("app/jobs/#{root_path}/#{feature_key}/#{concern_key}_job.rb", body, "job")
      end

      def write_policy(feature_key, concern_key, class_name)
        body = <<~RUBY
          # frozen_string_literal: true

          module #{root_module}
            class #{class_name}Policy < ApplicationPolicy
              def execute?
                user.present?
              end
            end
          end
        RUBY

        write("app/policies/#{root_path}/#{feature_key}/#{concern_key}_policy.rb", body, "policy")
      end

      def write_api_controller(feature_key, concern_key, class_name)
        controller_class = "#{class_name.pluralize}Controller"
        body = <<~RUBY
          # frozen_string_literal: true

          module Api
            module V1
              module #{root_module}
                class #{controller_class} < ApplicationController
                  def create
                    record = #{model_name.camelize}.find(params.require(:id))
                    authorize record, :execute?, policy_class: ::#{root_module}::#{class_name}Policy
                    ::#{root_module}::#{class_name}Service.call(
                      record: record,
                      action: params.require(:action_name),
                      payload: params.fetch(:payload, {}).permit!.to_h
                    )
                    head :accepted
                  end
                end
              end
            end
          end
        RUBY

        write("app/controllers/api/v1/#{root_path}/#{feature_key}/#{concern_key.pluralize}_controller.rb", body, "controller")
      end

      def dispatch_line(class_name)
        if options[:jobs]
          "#{root_module}::#{class_name}Job.perform_later(self, action.to_s, payload)"
        else
          "#{root_module}::#{class_name}Service.call(record: self, action: action, payload: payload)"
        end
      end

      def root_module
        options[:namespace].to_s.camelize
      end

      def root_path
        root_module.underscore
      end

      def write(path, body, artifact_type)
        writer.write(path, body, blueprint_key: project_type.key, artifact_type: artifact_type)
        say_status :create, path, :green
      end
    end
  end
end
