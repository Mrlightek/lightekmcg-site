#!/usr/bin/env bash
set -Eeuo pipefail

# Marlon Meta-Framework installer
#
# Run from the root of the Marlon gem or a Rails application containing it:
#   bash install_marlon_meta_framework.sh
#
# Optional environment variables:
#   MARLON_ROOT=/path/to/marlon
#   FORCE=1                      # overwrite files without making timestamped copies
#   SKIP_MIGRATIONS=1            # write files but do not run rails db:migrate
#   SKIP_SEED=1                  # write files but do not load the meta-framework seed
#
# The installer creates a database-driven application blueprint system:
# ProjectType -> CapabilityPack -> Feature -> BlueprintConcern
#                         \-> CapabilityPackDependency
#
# It also creates a generator that materializes selected blueprint concerns into
# model concerns, services, jobs, policies, and optional API controllers.

ROOT="${MARLON_ROOT:-$(pwd)}"
FORCE="${FORCE:-0}"
SKIP_MIGRATIONS="${SKIP_MIGRATIONS:-0}"
SKIP_SEED="${SKIP_SEED:-0}"
STAMP="$(date +%Y%m%d%H%M%S)"

cd "$ROOT"

if [[ ! -f "marlon.gemspec" && ! -f "Gemfile" ]]; then
  echo "error: run this script from the Marlon gem or Rails application root" >&2
  exit 1
fi

write_file() {
  local path="$1"
  local directory
  directory="$(dirname "$path")"
  mkdir -p "$directory"

  if [[ -f "$path" && "$FORCE" != "1" ]]; then
    cp "$path" "${path}.bak.${STAMP}"
    echo "backup: ${path}.bak.${STAMP}"
  fi

  cat > "$path"
  echo "write:  $path"
}

migration_prefix() {
  local offset="$1"
  date -u -d "+${offset} seconds" +%Y%m%d%H%M%S 2>/dev/null || ruby -e "puts (Time.now.utc + ${offset}).strftime('%Y%m%d%H%M%S')"
}

M1="$(migration_prefix 0)"
M2="$(migration_prefix 1)"
M3="$(migration_prefix 2)"
M4="$(migration_prefix 3)"
M5="$(migration_prefix 4)"
M6="$(migration_prefix 5)"
M7="$(migration_prefix 6)"
M8="$(migration_prefix 7)"

write_file "app/models/marlon/application_record.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
RUBY

write_file "app/models/marlon/project_type.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class ProjectType < ApplicationRecord
    self.table_name = "marlon_project_types"

    has_many :project_type_capability_packs,
      class_name: "Marlon::ProjectTypeCapabilityPack",
      dependent: :destroy,
      inverse_of: :project_type
    has_many :capability_packs,
      through: :project_type_capability_packs,
      class_name: "Marlon::CapabilityPack"

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }

    def resolved_capability_packs
      Marlon::Blueprint::Resolver.new(capability_packs).resolve
    end

    def resolved_features
      resolved_capability_packs.flat_map(&:features).uniq(&:id)
    end
  end
end
RUBY

write_file "app/models/marlon/capability_pack.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class CapabilityPack < ApplicationRecord
    self.table_name = "marlon_capability_packs"

    has_many :capability_pack_features,
      class_name: "Marlon::CapabilityPackFeature",
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :features,
      through: :capability_pack_features,
      class_name: "Marlon::Feature"

    has_many :outgoing_dependencies,
      class_name: "Marlon::CapabilityPackDependency",
      foreign_key: :capability_pack_id,
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :dependencies,
      through: :outgoing_dependencies,
      source: :dependency,
      class_name: "Marlon::CapabilityPack"

    has_many :incoming_dependencies,
      class_name: "Marlon::CapabilityPackDependency",
      foreign_key: :dependency_id,
      dependent: :destroy,
      inverse_of: :dependency

    has_many :project_type_capability_packs,
      class_name: "Marlon::ProjectTypeCapabilityPack",
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :project_types,
      through: :project_type_capability_packs,
      class_name: "Marlon::ProjectType"

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }
  end
end
RUBY

write_file "app/models/marlon/feature.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class Feature < ApplicationRecord
    self.table_name = "marlon_features"

    has_many :capability_pack_features,
      class_name: "Marlon::CapabilityPackFeature",
      dependent: :destroy,
      inverse_of: :feature
    has_many :capability_packs,
      through: :capability_pack_features,
      class_name: "Marlon::CapabilityPack"

    has_many :blueprint_concerns,
      class_name: "Marlon::BlueprintConcern",
      dependent: :destroy,
      inverse_of: :feature

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }
  end
end
RUBY

write_file "app/models/marlon/blueprint_concern.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class BlueprintConcern < ApplicationRecord
    self.table_name = "marlon_blueprint_concerns"

    belongs_to :feature,
      class_name: "Marlon::Feature",
      inverse_of: :blueprint_concerns

    validates :name, :key, :target_type, presence: true
    validates :key, uniqueness: { scope: :feature_id },
      format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :target_type, inclusion: { in: %w[model controller policy service job serializer graphql] }

    scope :active, -> { where(active: true) }

    def class_name
      (implementation_class.presence || key).to_s.camelize
    end
  end
end
RUBY

write_file "app/models/marlon/capability_pack_dependency.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class CapabilityPackDependency < ApplicationRecord
    self.table_name = "marlon_capability_pack_dependencies"

    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :outgoing_dependencies
    belongs_to :dependency,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :incoming_dependencies

    validates :dependency_id, uniqueness: { scope: :capability_pack_id }
    validate :cannot_depend_on_self

    private

    def cannot_depend_on_self
      errors.add(:dependency, "cannot be itself") if capability_pack_id == dependency_id
    end
  end
end
RUBY

write_file "app/models/marlon/capability_pack_feature.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class CapabilityPackFeature < ApplicationRecord
    self.table_name = "marlon_capability_pack_features"

    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :capability_pack_features
    belongs_to :feature,
      class_name: "Marlon::Feature",
      inverse_of: :capability_pack_features

    validates :feature_id, uniqueness: { scope: :capability_pack_id }
  end
end
RUBY

write_file "app/models/marlon/project_type_capability_pack.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class ProjectTypeCapabilityPack < ApplicationRecord
    self.table_name = "marlon_project_type_capability_packs"

    belongs_to :project_type,
      class_name: "Marlon::ProjectType",
      inverse_of: :project_type_capability_packs
    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :project_type_capability_packs

    validates :capability_pack_id, uniqueness: { scope: :project_type_id }
  end
end
RUBY

write_file "db/migrate/${M1}_create_marlon_project_types.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonProjectTypes < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_project_types do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_project_types, :key, unique: true
  end
end
RUBY

write_file "db/migrate/${M2}_create_marlon_capability_packs.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonCapabilityPacks < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_packs do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_capability_packs, :key, unique: true
  end
end
RUBY

write_file "db/migrate/${M3}_create_marlon_features.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_features do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_features, :key, unique: true
  end
end
RUBY

write_file "db/migrate/${M4}_create_marlon_blueprint_concerns.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonBlueprintConcerns < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_blueprint_concerns do |t|
      t.references :feature, null: false, foreign_key: { to_table: :marlon_features }
      t.string :key, null: false
      t.string :name, null: false
      t.string :target_type, null: false, default: "model"
      t.string :implementation_class
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_blueprint_concerns, [:feature_id, :key], unique: true,
      name: "idx_marlon_concerns_feature_key"
  end
end
RUBY

write_file "db/migrate/${M5}_create_marlon_capability_pack_dependencies.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonCapabilityPackDependencies < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_pack_dependencies do |t|
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.references :dependency, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.timestamps
    end

    add_index :marlon_capability_pack_dependencies,
      [:capability_pack_id, :dependency_id], unique: true,
      name: "idx_marlon_pack_dependencies_unique"
  end
end
RUBY

write_file "db/migrate/${M6}_create_marlon_capability_pack_features.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonCapabilityPackFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_capability_pack_features do |t|
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.references :feature, null: false, foreign_key: { to_table: :marlon_features }, index: false
      t.integer :position, null: false, default: 0
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_capability_pack_features,
      [:capability_pack_id, :feature_id], unique: true,
      name: "idx_marlon_pack_features_unique"
  end
end
RUBY

write_file "db/migrate/${M7}_create_marlon_project_type_capability_packs.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonProjectTypeCapabilityPacks < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_project_type_capability_packs do |t|
      t.references :project_type, null: false, foreign_key: { to_table: :marlon_project_types }, index: false
      t.references :capability_pack, null: false, foreign_key: { to_table: :marlon_capability_packs }, index: false
      t.integer :position, null: false, default: 0
      t.json :configuration, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_project_type_capability_packs,
      [:project_type_id, :capability_pack_id], unique: true,
      name: "idx_marlon_project_type_packs_unique"
  end
end
RUBY

write_file "db/migrate/${M8}_create_marlon_generated_artifacts.rb" <<'RUBY'
# frozen_string_literal: true

class CreateMarlonGeneratedArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_generated_artifacts do |t|
      t.string :blueprint_key, null: false
      t.string :artifact_type, null: false
      t.string :path, null: false
      t.string :checksum
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_generated_artifacts,
      [:blueprint_key, :path], unique: true,
      name: "idx_marlon_generated_artifacts_unique"
  end
end
RUBY

write_file "app/models/marlon/generated_artifact.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  class GeneratedArtifact < ApplicationRecord
    self.table_name = "marlon_generated_artifacts"

    validates :blueprint_key, :artifact_type, :path, presence: true
    validates :path, uniqueness: { scope: :blueprint_key }
  end
end
RUBY

write_file "app/services/marlon/blueprint/resolver.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  module Blueprint
    class Resolver
      class CircularDependencyError < StandardError; end

      def initialize(capability_packs)
        @capability_packs = Array(capability_packs)
      end

      def resolve
        resolved = []
        visiting = []

        @capability_packs.each do |pack|
          visit(pack, resolved:, visiting:)
        end

        resolved
      end

      private

      def visit(pack, resolved:, visiting:)
        return if resolved.include?(pack)

        if visiting.include?(pack)
          cycle = (visiting.drop_while { |item| item != pack } + [pack]).map(&:key)
          raise CircularDependencyError, "Circular capability dependency: #{cycle.join(' -> ')}"
        end

        visiting << pack
        pack.dependencies.order(:key).each do |dependency|
          visit(dependency, resolved:, visiting:)
        end
        visiting.pop
        resolved << pack
      end
    end
  end
end
RUBY

write_file "app/services/marlon/blueprint/compiler.rb" <<'RUBY'
# frozen_string_literal: true

module Marlon
  module Blueprint
    class Compiler
      def initialize(project_type:, selected_pack_keys: [], selected_feature_keys: [])
        @project_type = project_type
        @selected_pack_keys = Array(selected_pack_keys).map(&:to_s)
        @selected_feature_keys = Array(selected_feature_keys).map(&:to_s)
      end

      def call
        packs = selected_packs
        resolved_packs = Resolver.new(packs).resolve
        features = resolved_packs.flat_map(&:features).uniq(&:id)
        features.select! { |feature| @selected_feature_keys.include?(feature.key) } if @selected_feature_keys.any?

        {
          project_type: serialize_project_type,
          capability_packs: resolved_packs.map { |pack| serialize_pack(pack) },
          features: features.map { |feature| serialize_feature(feature) },
          concerns: features.flat_map(&:blueprint_concerns).select(&:active?).map { |concern| serialize_concern(concern) }
        }
      end

      private

      def selected_packs
        base = @project_type.capability_packs.active
        return base if @selected_pack_keys.empty?

        selected = Marlon::CapabilityPack.active.where(key: @selected_pack_keys)
        missing = @selected_pack_keys - selected.pluck(:key)
        raise ArgumentError, "Unknown capability packs: #{missing.join(', ')}" if missing.any?
        selected
      end

      def serialize_project_type
        @project_type.slice(:key, :name, :description, :metadata)
      end

      def serialize_pack(pack)
        pack.slice(:key, :name, :description, :metadata)
      end

      def serialize_feature(feature)
        feature.slice(:key, :name, :description, :metadata)
      end

      def serialize_concern(concern)
        concern.slice(:key, :name, :target_type, :implementation_class, :description, :configuration)
          .merge(feature_key: concern.feature.key)
      end
    end
  end
end
RUBY

write_file "app/services/marlon/blueprint/file_writer.rb" <<'RUBY'
# frozen_string_literal: true

require "digest"
require "fileutils"

module Marlon
  module Blueprint
    class FileWriter
      def initialize(root: Rails.root, force: false)
        @root = Pathname(root)
        @force = force
      end

      def write(relative_path, content, blueprint_key:, artifact_type:)
        path = @root.join(relative_path)
        FileUtils.mkdir_p(path.dirname)

        if path.exist? && !@force
          raise Thor::Error, "Refusing to overwrite #{relative_path}; pass --force"
        end

        path.write(content)
        checksum = Digest::SHA256.hexdigest(content)

        Marlon::GeneratedArtifact.upsert(
          {
            blueprint_key: blueprint_key,
            artifact_type: artifact_type,
            path: relative_path.to_s,
            checksum: checksum,
            metadata: {},
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[blueprint_key path]
        )

        relative_path
      end
    end
  end
end
RUBY

write_file "lib/generators/marlon/meta_framework/meta_framework_generator.rb" <<'RUBY'
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
RUBY

write_file "db/seeds/marlon_meta_framework.rb" <<'RUBY'
# frozen_string_literal: true

# Idempotent seed for the Marlon meta-framework.
# Run with:
#   bin/rails runner db/seeds/marlon_meta_framework.rb

PACKS = {
  crm: { name: "CRM", depends_on: [], features: %i[customers contacts companies locations opportunities quotes customer_portal communication_history] },
  identity: { name: "Identity & Access", depends_on: [], features: %i[users roles permissions rbac sso oauth ldap active_directory mfa service_accounts api_keys privileged_access] },
  automation: { name: "Automation", depends_on: [], features: %i[workflow_builder event_bus webhooks scheduled_workflows approval_workflows conditional_workflows runbooks integrations] },
  monitoring: { name: "Monitoring & Observability", depends_on: %i[automation], features: %i[health_checks uptime metrics logs tracing thresholds alerts notifications dashboards status_pages] },
  assets: { name: "Asset Management", depends_on: %i[crm], features: %i[hardware_assets software_assets licenses inventory procurement vendors warranties depreciation asset_lifecycle asset_assignments] },
  security: { name: "Cybersecurity", depends_on: %i[identity monitoring], features: %i[security_baselines vulnerability_scanning threat_detection threat_intelligence siem ids_ips security_incidents incident_response risk_assessments penetration_testing zero_trust security_awareness phishing_campaigns] },
  compliance: { name: "Compliance", depends_on: %i[identity security], features: %i[control_library policies evidence audit_programs findings remediation retention privacy_requests hipaa pci_dss soc2 iso27001 nist cis gdpr] },
  ticketing: { name: "Service Desk & Ticketing", depends_on: %i[crm identity automation], features: %i[tickets queues assignments priorities categories sla escalations work_logs time_tracking approvals incident_management problem_management change_management service_catalog] },
  knowledge: { name: "Knowledge Management", depends_on: %i[identity], features: %i[articles faqs runbooks documentation categories attachments versioning approvals search feedback] },
  billing: { name: "Billing & Revenue", depends_on: %i[crm], features: %i[plans subscriptions usage_metering invoices payments taxes credits refunds renewals collections revenue_recognition] },
  contracts: { name: "Contracts & SLAs", depends_on: %i[crm billing], features: %i[contracts terms pricing service_levels signatures amendments renewals obligations entitlements] },
  reporting: { name: "Reporting & Analytics", depends_on: [], features: %i[dashboards analytics kpis scheduled_reports exports audit_reports executive_reports data_snapshots] },
  backup_dr: { name: "Backup & Disaster Recovery", depends_on: %i[monitoring automation security], features: %i[backup_policies backups snapshots replication retention offsite_storage restores recovery_plans recovery_testing recovery_objectives] },
  networking: { name: "Network Operations", depends_on: %i[assets monitoring security], features: %i[firewalls switches routers wireless vlans vpn sdwan ipam dns dhcp configuration_backups topology] },
  rmm: { name: "Remote Monitoring & Management", depends_on: %i[assets monitoring automation security], features: %i[endpoint_agents endpoint_monitoring service_monitoring performance_monitoring patch_management script_execution scheduled_tasks software_deployment remote_shell remote_support remediation_policies] },
  mdm: { name: "Mobile Device Management", depends_on: %i[assets identity automation monitoring security], features: %i[device_enrollment device_inventory device_groups ownership_models device_profiles policy_management compliance_evaluation application_management certificate_management remote_lock remote_wipe lost_mode kiosk_mode os_updates patching encryption password_policy wifi_profiles vpn_profiles email_profiles peripheral_controls geofencing device_health device_attestation command_tracking] },
  cloud: { name: "Cloud Services", depends_on: %i[identity monitoring automation security billing], features: %i[cloud_accounts subscriptions resource_inventory compute storage databases cloud_networking load_balancers autoscaling iam kubernetes containers serverless secrets cost_management budgets provisioning deprovisioning] },
  hosting: { name: "Web Hosting", depends_on: %i[crm billing monitoring automation backup_dr security], features: %i[hosting_accounts service_plans domains domain_registration dns_zones dns_records ssl_certificates websites staging_sites deployments ftp_accounts ssh_access email_hosting mailboxes databases cron_jobs runtimes control_panels wordpress] },
  devops: { name: "DevOps Platform", depends_on: %i[cloud monitoring automation security], features: %i[repositories pipelines builds tests artifacts registries environments deployments releases feature_flags infrastructure_as_code secrets change_approvals rollback] },
  data_center: { name: "Data Center Operations", depends_on: %i[assets monitoring networking], features: %i[facilities rooms racks rack_units power_circuits cooling environmental_sensors capacity_planning cross_connects smart_hands maintenance_windows access_logs] },
  field_service: { name: "Field Service", depends_on: %i[crm assets ticketing], features: %i[work_orders dispatch technicians skills territories routes appointments parts_usage checklists signatures service_reports] },
  commerce: { name: "Commerce", depends_on: %i[crm billing], features: %i[products variants catalogs pricing inventory carts checkout orders fulfillment shipping returns exchanges promotions loyalty fraud_review] },
  healthcare: { name: "Healthcare Operations", depends_on: %i[crm identity compliance billing reporting], features: %i[patients consent guardians appointments encounters clinical_notes diagnoses orders results referrals care_plans claims eligibility remittance patient_messages] },
  education: { name: "Education", depends_on: %i[crm identity billing reporting], features: %i[learners instructors courses programs enrollment cohorts schedules lessons assignments assessments grades attendance credentials learning_progress] },
  projects: { name: "Project Delivery", depends_on: %i[crm contracts billing reporting], features: %i[projects scopes milestones deliverables tasks dependencies resources allocations time_entries expenses utilization status_reports client_approvals] }
}.freeze

PROJECT_TYPES = {
  managed_it_services: { name: "Managed IT Services (MSP)", packs: %i[crm ticketing knowledge assets mdm rmm networking backup_dr contracts billing reporting compliance field_service] },
  cybersecurity_services: { name: "Cybersecurity Services / MSSP", packs: %i[crm ticketing security compliance identity monitoring automation knowledge contracts billing reporting] },
  web_hosting_provider: { name: "Web Hosting Provider", packs: %i[hosting ticketing knowledge reporting contracts] },
  cloud_service_provider: { name: "Cloud Service Provider", packs: %i[cloud ticketing knowledge contracts compliance reporting backup_dr devops] },
  devops_platform: { name: "DevOps Platform", packs: %i[devops ticketing knowledge reporting compliance] },
  network_operations: { name: "Network Operations Center", packs: %i[networking ticketing rmm knowledge contracts billing reporting field_service] },
  data_center: { name: "Data Center", packs: %i[data_center ticketing contracts billing reporting security field_service] },
  saas: { name: "Software as a Service", packs: %i[crm identity billing ticketing knowledge automation monitoring security reporting] },
  ecommerce: { name: "E-commerce", packs: %i[commerce ticketing knowledge reporting automation] },
  healthcare: { name: "Healthcare", packs: %i[healthcare ticketing knowledge automation] },
  education: { name: "Education", packs: %i[education ticketing knowledge automation] },
  professional_services: { name: "Professional Services", packs: %i[projects ticketing knowledge automation] }
}.freeze

ActiveRecord::Base.transaction do
  PACKS.each do |key, definition|
    pack = Marlon::CapabilityPack.find_or_initialize_by(key: key.to_s)
    pack.update!(name: definition.fetch(:name), active: true)

    definition.fetch(:features).each_with_index do |feature_key, index|
      feature = Marlon::Feature.find_or_initialize_by(key: feature_key.to_s)
      feature.update!(name: feature_key.to_s.humanize, active: true)

      Marlon::CapabilityPackFeature.find_or_initialize_by(capability_pack: pack, feature: feature)
        .update!(position: index)

      concern = Marlon::BlueprintConcern.find_or_initialize_by(feature: feature, key: feature_key.to_s)
      concern.update!(
        name: feature_key.to_s.humanize,
        target_type: "model",
        implementation_class: feature_key.to_s.camelize,
        active: true,
        configuration: {
          generates: %w[concern service job policy],
          queue: "default",
          idempotent: true
        }
      )
    end
  end

  PACKS.each do |key, definition|
    pack = Marlon::CapabilityPack.find_by!(key: key.to_s)
    definition.fetch(:depends_on).each do |dependency_key|
      dependency = Marlon::CapabilityPack.find_by!(key: dependency_key.to_s)
      Marlon::CapabilityPackDependency.find_or_create_by!(capability_pack: pack, dependency: dependency)
    end
  end

  PROJECT_TYPES.each do |key, definition|
    project_type = Marlon::ProjectType.find_or_initialize_by(key: key.to_s)
    project_type.update!(name: definition.fetch(:name), active: true)

    definition.fetch(:packs).each_with_index do |pack_key, index|
      pack = Marlon::CapabilityPack.find_by!(key: pack_key.to_s)
      Marlon::ProjectTypeCapabilityPack.find_or_initialize_by(project_type: project_type, capability_pack: pack)
        .update!(position: index)
    end
  end
end

puts "Seeded #{Marlon::ProjectType.count} project types"
puts "Seeded #{Marlon::CapabilityPack.count} capability packs"
puts "Seeded #{Marlon::Feature.count} features"
puts "Seeded #{Marlon::BlueprintConcern.count} blueprint concerns"
RUBY

write_file "lib/tasks/marlon_meta_framework.rake" <<'RUBY'
# frozen_string_literal: true

namespace :marlon do
  namespace :meta do
    desc "Seed the Marlon meta-framework catalog"
    task seed: :environment do
      load Rails.root.join("db/seeds/marlon_meta_framework.rb")
    end

    desc "Validate capability-pack dependencies"
    task validate: :environment do
      Marlon::CapabilityPack.find_each do |pack|
        Marlon::Blueprint::Resolver.new([pack]).resolve
      end
      puts "Marlon capability graph is valid"
    end

    desc "Print a project blueprint; PROJECT_TYPE=managed_it_services"
    task inspect: :environment do
      key = ENV.fetch("PROJECT_TYPE", "managed_it_services")
      project_type = Marlon::ProjectType.find_by!(key: key)
      blueprint = Marlon::Blueprint::Compiler.new(project_type: project_type).call
      puts JSON.pretty_generate(blueprint)
    end
  end
end
RUBY

write_file "config/initializers/marlon_meta_framework.rb" <<'RUBY'
# frozen_string_literal: true

# Configuration namespace for future Marlon builder adapters.
module Marlon
  mattr_accessor :meta_framework_namespace, default: "Marlon"
  mattr_accessor :meta_framework_queue, default: :default
  mattr_accessor :meta_framework_generate_policies, default: true
end
RUBY

write_file "docs/MARLON_META_FRAMEWORK.md" <<'MARKDOWN'
# Marlon Meta-Framework

The meta-framework stores application architecture as data:

```text
ProjectType
  -> ProjectTypeCapabilityPack
    -> CapabilityPack
      -> CapabilityPackDependency
      -> CapabilityPackFeature
        -> Feature
          -> BlueprintConcern
```

## Install

```bash
bash install_marlon_meta_framework.sh
```

The script creates timestamped backups before replacing an existing file. Set
`FORCE=1` to overwrite without backups.

## Seed

```bash
bin/rails marlon:meta:seed
bin/rails marlon:meta:validate
```

## Inspect a compiled blueprint

```bash
PROJECT_TYPE=managed_it_services bin/rails marlon:meta:inspect
```

## Generate an application layer

```bash
bin/rails generate marlon:meta_framework managed_it_services Device
```

Generate only MDM and RMM, including their dependencies:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --packs mdm,rmm
```

Generate selected device functions:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --packs mdm \
  --features device_enrollment,policy_management,remote_lock,remote_wipe
```

Generate API controllers and policies:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --api \
  --policies
```

## Builder integration

Your project builder should persist or pass:

```ruby
{
  project_type_key: "managed_it_services",
  capability_pack_keys: %w[mdm rmm ticketing],
  feature_keys: %w[device_enrollment remote_lock remote_wipe]
}
```

Compile that selection with:

```ruby
project_type = Marlon::ProjectType.find_by!(key: params[:project_type_key])
blueprint = Marlon::Blueprint::Compiler.new(
  project_type: project_type,
  selected_pack_keys: params[:capability_pack_keys],
  selected_feature_keys: params[:feature_keys]
).call
```

The compiler resolves dependencies in topological order and removes duplicate
packs and features. The generator records generated paths and SHA-256 checksums
in `marlon_generated_artifacts`.

## Extending the framework

Add new records rather than changing generator logic:

1. Create a `Marlon::CapabilityPack`.
2. Attach dependencies.
3. Create or reuse `Marlon::Feature` records.
4. Attach one or more `Marlon::BlueprintConcern` records to each feature.
5. Attach the pack to one or more project types.

A future renderer can inspect `BlueprintConcern#target_type` and
`#configuration` to generate serializers, GraphQL types, navigation, routes,
permissions, dashboards, or workflow definitions.
MARKDOWN

# Ensure the gem/application loads app/services and app/models if needed.
if [[ -f "lib/marlon/engine.rb" ]]; then
  echo "note: verify lib/marlon/engine.rb eager-loads app/services and app/models"
fi

if [[ "$SKIP_MIGRATIONS" != "1" ]] && [[ -x "bin/rails" ]]; then
  echo "run:    bin/rails db:migrate"
  bin/rails db:migrate
else
  echo "skip:   migrations"
fi

if [[ "$SKIP_SEED" != "1" ]] && [[ -x "bin/rails" ]]; then
  echo "run:    bin/rails runner db/seeds/marlon_meta_framework.rb"
  bin/rails runner db/seeds/marlon_meta_framework.rb
else
  echo "skip:   seed"
fi

cat <<'TEXT'

Marlon meta-framework installed.

Next commands:
  bin/rails marlon:meta:validate
  PROJECT_TYPE=managed_it_services bin/rails marlon:meta:inspect
  bin/rails generate marlon:meta_framework managed_it_services Device --packs mdm,rmm

The prior capability-pack registry can remain temporarily for compatibility,
but the database-backed catalog is now the source of truth.
TEXT
