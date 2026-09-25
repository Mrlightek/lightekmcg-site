#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_foundation_backup_${STAMP}"
mkdir -p "$BACKUP"

cp config/routes.rb "$BACKUP/routes.rb"

mkdir -p \
  app/models \
  app/services/gatekeeper/capabilities \
  app/jobs/gatekeeper \
  app/controllers/gatekeeper \
  app/views/gatekeeper/infrastructure \
  app/views/gatekeeper/nodes \
  app/views/gatekeeper/projects \
  lib/scripts/gatekeeper \
  lib/tasks \
  db/migrate

MIGRATION="$(find db/migrate -maxdepth 1 -type f -name '*create_gatekeeper_infrastructure*.rb' | head -1 || true)"
if [[ -z "$MIGRATION" ]]; then
  MIGRATION="db/migrate/$(date +%Y%m%d%H%M%S)_create_gatekeeper_infrastructure.rb"
  cat > "$MIGRATION" <<'RUBY'
class CreateGatekeeperInfrastructure < ActiveRecord::Migration[8.0]
  def change
    create_table :gatekeeper_nodes do |t|
      t.string :name, null: false
      t.string :hostname
      t.string :ip_address, null: false
      t.string :ssh_user, null: false, default: "root"
      t.integer :ssh_port, null: false, default: 22
      t.string :ssh_key_path
      t.string :provider
      t.string :provider_id
      t.string :region
      t.string :status, null: false, default: "unknown"
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_healthcheck_at
      t.timestamps
    end

    add_index :gatekeeper_nodes, :name, unique: true
    add_index :gatekeeper_nodes, :status

    create_table :gatekeeper_projects do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.string :name, null: false
      t.string :repository, null: false
      t.string :branch, null: false, default: "main"
      t.string :domain, null: false
      t.string :app_root, null: false
      t.string :app_user, null: false, default: "lightek"
      t.string :ruby_version, null: false, default: "3.3.6"
      t.string :rails_env, null: false, default: "production"
      t.string :apache_service_name, null: false, default: "apache2"
      t.string :sidekiq_service_name
      t.string :status, null: false, default: "unknown"
      t.string :deployed_sha
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_deployed_at
      t.datetime :last_healthcheck_at
      t.timestamps
    end

    add_index :gatekeeper_projects, :name, unique: true
    add_index :gatekeeper_projects, :domain, unique: true
    add_index :gatekeeper_projects, :status

    create_table :gatekeeper_operations do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.references :gatekeeper_project, null: true, foreign_key: true
      t.string :capability, null: false
      t.string :requested_by, null: false
      t.string :status, null: false, default: "queued"
      t.text :command
      t.text :output
      t.integer :exit_status
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.string :error_class
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :gatekeeper_operations, :capability
    add_index :gatekeeper_operations, :status
    add_index :gatekeeper_operations, :created_at

    create_table :gatekeeper_escalations do |t|
      t.references :gatekeeper_operation, null: false, foreign_key: true
      t.string :category, null: false, default: "unknown_condition"
      t.string :status, null: false, default: "open"
      t.text :reason, null: false
      t.text :resolution
      t.boolean :capability_created, null: false, default: false
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :gatekeeper_escalations, :status
    add_index :gatekeeper_escalations, :category
  end
end
RUBY
fi

cat > app/models/gatekeeper_node.rb <<'RUBY'
class GatekeeperNode < ApplicationRecord
  STATUSES = %w[unknown provisioning healthy degraded unreachable failed].freeze

  has_many :gatekeeper_projects, dependent: :restrict_with_error
  has_many :gatekeeper_operations, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :ip_address, :ssh_user, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  def local?
    %w[127.0.0.1 ::1 localhost].include?(ip_address.to_s) ||
      ip_address.to_s == ENV["GATEKEEPER_LOCAL_NODE_IP"].to_s
  end

  def display_host
    hostname.presence || ip_address
  end
end
RUBY

cat > app/models/gatekeeper_project.rb <<'RUBY'
class GatekeeperProject < ApplicationRecord
  STATUSES = %w[unknown provisioning healthy degraded deploying failed].freeze

  belongs_to :gatekeeper_node
  has_many :gatekeeper_operations, dependent: :nullify

  validates :name, :repository, :domain, :app_root, :ruby_version, presence: true
  validates :name, :domain, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def sidekiq_service
    sidekiq_service_name.presence || "#{name}-sidekiq"
  end

  def health_url
    metadata["health_url"].presence || "https://#{domain}/up"
  end
end
RUBY

cat > app/models/gatekeeper_operation.rb <<'RUBY'
class GatekeeperOperation < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :gatekeeper_node
  belongs_to :gatekeeper_project, optional: true
  has_one :gatekeeper_escalation, dependent: :destroy

  validates :capability, :requested_by, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
end
RUBY

cat > app/models/gatekeeper_escalation.rb <<'RUBY'
class GatekeeperEscalation < ApplicationRecord
  STATUSES = %w[open resolved dismissed].freeze
  CATEGORIES = %w[unknown_condition missing_capability permission_required recovery_exhausted low_confidence].freeze

  belongs_to :gatekeeper_operation

  validates :reason, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :category, inclusion: { in: CATEGORIES }

  scope :open, -> { where(status: "open") }

  def resolve!(resolution:, capability_created: false)
    update!(
      status: "resolved",
      resolution: resolution,
      capability_created: capability_created,
      resolved_at: Time.current
    )
  end
end
RUBY

cat > app/services/gatekeeper/capability_registry.rb <<'RUBY'
module Gatekeeper
  class CapabilityRegistry
    REGISTRY = {
      "deploy_project" => "Gatekeeper::Capabilities::DeployProject",
      "healthcheck_project" => "Gatekeeper::Capabilities::HealthcheckProject"
    }.freeze

    class UnknownCapability < StandardError; end

    def self.fetch!(name)
      class_name = REGISTRY[name.to_s]
      raise UnknownCapability, "Unregistered Gatekeeper capability: #{name}" unless class_name
      class_name.constantize
    end

    def self.names
      REGISTRY.keys
    end
  end
end
RUBY

cat > app/services/gatekeeper/command_runner.rb <<'RUBY'
require "open3"

module Gatekeeper
  class CommandRunner
    Result = Data.define(:command, :stdout, :stderr, :exit_status) do
      def success? = exit_status.to_i.zero?
      def output = [stdout, stderr].reject(&:blank?).join("\n")
    end

    def self.call(node:, command:)
      node.local? ? local(command) : remote(node, command)
    end

    def self.local(command)
      stdout, stderr, status = Open3.capture3(command)
      Result.new(command:, stdout:, stderr:, exit_status: status.exitstatus)
    end
    private_class_method :local

    def self.remote(node, command)
      require "net/ssh"

      stdout = +""
      stderr = +""
      exit_status = 255

      options = {
        port: node.ssh_port,
        non_interactive: true,
        verify_host_key: :accept_new
      }
      options[:keys] = [node.ssh_key_path] if node.ssh_key_path.present?

      Net::SSH.start(node.ip_address, node.ssh_user, **options) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_channel, success|
            raise "SSH command could not be started" unless success
            ch.on_data { |_c, data| stdout << data }
            ch.on_extended_data { |_c, _type, data| stderr << data }
            ch.on_request("exit-status") { |_c, data| exit_status = data.read_long }
          end
        end
        channel.wait
      end

      Result.new(command:, stdout:, stderr:, exit_status:)
    end
    private_class_method :remote
  end
end
RUBY

cat > app/services/gatekeeper/executor.rb <<'RUBY'
module Gatekeeper
  class Executor
    def self.call(capability:, node:, project: nil, requested_by:, parameters: {})
      operation = nil
      capability_name = capability.to_s
      capability_class = CapabilityRegistry.fetch!(capability_name)

      operation = GatekeeperOperation.create!(
        gatekeeper_node: node,
        gatekeeper_project: project,
        capability: capability_name,
        requested_by: requested_by.to_s,
        parameters: parameters.to_h,
        status: "running",
        started_at: Time.current
      )

      result = capability_class.call(node:, project:, parameters: parameters.to_h)

      operation.update!(
        status: "succeeded",
        command: result[:command],
        output: result[:output],
        exit_status: result[:exit_status],
        result: result.except(:command, :output, :exit_status),
        completed_at: Time.current
      )

      operation
    rescue StandardError => e
      if operation
        operation.update!(
          status: "failed",
          error_class: e.class.name,
          error_message: e.message,
          completed_at: Time.current
        )
        operation.create_gatekeeper_escalation!(
          category: "recovery_exhausted",
          reason: "#{capability_name} failed: #{e.class}: #{e.message}"
        )
      end
      raise
    end
  end
end
RUBY

cat > app/services/gatekeeper/metrics.rb <<'RUBY'
module Gatekeeper
  class Metrics
    def self.summary(since: 7.days.ago)
      operations = GatekeeperOperation.where(created_at: since..)
      escalations = GatekeeperEscalation.where(created_at: since..)
      total = operations.count
      interventions = escalations.count

      {
        operations: total,
        succeeded: operations.where(status: "succeeded").count,
        failed: operations.where(status: "failed").count,
        open_escalations: GatekeeperEscalation.open.count,
        human_interventions: interventions,
        marlon_dependency_rate: total.zero? ? 0.0 : interventions.to_f / total
      }
    end
  end
end
RUBY

cat > app/services/gatekeeper/capabilities/deploy_project.rb <<'RUBY'
require "shellwords"

module Gatekeeper
  module Capabilities
    class DeployProject
      def self.call(node:, project:, parameters: {})
        raise ArgumentError, "project is required" unless project

        project.update!(status: "deploying")
        script = File.join(project.app_root, "lib/scripts/gatekeeper/deploy_project.sh")

        env = {
          APP_ROOT: project.app_root,
          APP_USER: project.app_user,
          APP_NAME: project.name,
          APP_DOMAIN: project.domain,
          APP_BRANCH: parameters["branch"].presence || project.branch,
          RUBY_VERSION: project.ruby_version,
          RAILS_ENV: project.rails_env,
          APACHE_SERVICE: project.apache_service_name,
          SIDEKIQ_SERVICE: project.sidekiq_service
        }

        prefix = env.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")
        command = "sudo #{prefix} bash #{Shellwords.escape(script)}"
        execution = CommandRunner.call(node:, command:)

        unless execution.success?
          project.update!(status: "failed")
          raise "deploy failed with exit #{execution.exit_status}: #{execution.output}"
        end

        sha = execution.stdout.to_s[/GATEKEEPER_DEPLOYED_SHA=([0-9a-f]+)/, 1]

        project.update!(
          status: "healthy",
          deployed_sha: sha.presence || project.deployed_sha,
          last_deployed_at: Time.current,
          last_healthcheck_at: Time.current
        )
        node.update!(status: "healthy", last_healthcheck_at: Time.current)

        {
          command: execution.command,
          output: execution.output,
          exit_status: execution.exit_status,
          deployed_sha: sha,
          healthy: true
        }
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/capabilities/healthcheck_project.rb <<'RUBY'
require "shellwords"

module Gatekeeper
  module Capabilities
    class HealthcheckProject
      def self.call(node:, project:, parameters: {})
        raise ArgumentError, "project is required" unless project

        script = File.join(project.app_root, "lib/scripts/gatekeeper/healthcheck_project.sh")
        prefix = {
          APP_ROOT: project.app_root,
          APP_DOMAIN: project.domain,
          APACHE_SERVICE: project.apache_service_name,
          SIDEKIQ_SERVICE: project.sidekiq_service
        }.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")

        command = "sudo #{prefix} bash #{Shellwords.escape(script)}"
        execution = CommandRunner.call(node:, command:)

        unless execution.success?
          project.update!(status: "degraded", last_healthcheck_at: Time.current)
          node.update!(status: "degraded", last_healthcheck_at: Time.current)
          raise "healthcheck failed: #{execution.output}"
        end

        project.update!(status: "healthy", last_healthcheck_at: Time.current)
        node.update!(status: "healthy", last_healthcheck_at: Time.current)

        {
          command: execution.command,
          output: execution.output,
          exit_status: execution.exit_status,
          healthy: true
        }
      end
    end
  end
end
RUBY

cat > app/jobs/gatekeeper/deploy_project_job.rb <<'RUBY'
module Gatekeeper
  class DeployProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id, requested_by: "gatekeeper", parameters: {})
      project = GatekeeperProject.find(project_id)
      Executor.call(
        capability: "deploy_project",
        node: project.gatekeeper_node,
        project:,
        requested_by:,
        parameters:
      )
    end
  end
end
RUBY

cat > app/jobs/gatekeeper/healthcheck_project_job.rb <<'RUBY'
module Gatekeeper
  class HealthcheckProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id, requested_by: "gatekeeper")
      project = GatekeeperProject.find(project_id)
      Executor.call(
        capability: "healthcheck_project",
        node: project.gatekeeper_node,
        project:,
        requested_by:
      )
    end
  end
end
RUBY

cat > app/controllers/gatekeeper/infrastructure_controller.rb <<'RUBY'
module Gatekeeper
  class InfrastructureController < ApplicationController
    def index
      @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
      @operations = GatekeeperOperation.includes(:gatekeeper_node, :gatekeeper_project).recent_first.limit(20)
      @escalations = GatekeeperEscalation.open.includes(:gatekeeper_operation)
      @metrics = Metrics.summary
    end
  end
end
RUBY

cat > app/controllers/gatekeeper/nodes_controller.rb <<'RUBY'
module Gatekeeper
  class NodesController < ApplicationController
    before_action :set_node, only: %i[show edit update destroy]

    def index = @nodes = GatekeeperNode.order(:name)
    def show = @projects = @node.gatekeeper_projects.order(:name)
    def new = @node = GatekeeperNode.new(ssh_user: "root", ssh_port: 22)
    def edit; end

    def create
      @node = GatekeeperNode.new(node_params)
      return redirect_to(gatekeeper_node_path(@node), notice: "Gatekeeper node created.") if @node.save
      render :new, status: :unprocessable_entity
    end

    def update
      return redirect_to(gatekeeper_node_path(@node), notice: "Gatekeeper node updated.") if @node.update(node_params)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @node.destroy!
      redirect_to gatekeeper_nodes_path, notice: "Gatekeeper node removed."
    end

    private

    def set_node = @node = GatekeeperNode.find(params[:id])

    def node_params
      params.expect(gatekeeper_node: [
        :name, :hostname, :ip_address, :ssh_user, :ssh_port,
        :ssh_key_path, :provider, :provider_id, :region
      ])
    end
  end
end
RUBY

cat > app/controllers/gatekeeper/projects_controller.rb <<'RUBY'
module Gatekeeper
  class ProjectsController < ApplicationController
    before_action :set_project, only: %i[show edit update destroy deploy healthcheck]

    def index = @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)

    def show
      @operations = @project.gatekeeper_operations.recent_first.limit(25)
    end

    def new
      @project = GatekeeperProject.new(
        gatekeeper_node_id: params[:gatekeeper_node_id],
        branch: "main",
        ruby_version: "3.3.6",
        rails_env: "production",
        app_user: "lightek",
        apache_service_name: "apache2"
      )
    end

    def edit; end

    def create
      @project = GatekeeperProject.new(project_params)
      return redirect_to(gatekeeper_project_path(@project), notice: "Gatekeeper project created.") if @project.save
      render :new, status: :unprocessable_entity
    end

    def update
      return redirect_to(gatekeeper_project_path(@project), notice: "Gatekeeper project updated.") if @project.update(project_params)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @project.destroy!
      redirect_to gatekeeper_projects_path, notice: "Gatekeeper project removed."
    end

    def deploy
      DeployProjectJob.perform_later(
        @project.id,
        requested_by: requester_name,
        parameters: { "branch" => @project.branch }
      )
      redirect_to gatekeeper_project_path(@project), notice: "Deployment queued."
    end

    def healthcheck
      HealthcheckProjectJob.perform_later(@project.id, requested_by: requester_name)
      redirect_to gatekeeper_project_path(@project), notice: "Healthcheck queued."
    end

    private

    def set_project = @project = GatekeeperProject.find(params[:id])

    def requester_name
      respond_to?(:current_user) && current_user ? "user:#{current_user.id}" : "gatekeeper_dashboard"
    end

    def project_params
      params.expect(gatekeeper_project: [
        :gatekeeper_node_id, :name, :repository, :branch, :domain,
        :app_root, :app_user, :ruby_version, :rails_env,
        :apache_service_name, :sidekiq_service_name
      ])
    end
  end
end
RUBY

cat > app/views/gatekeeper/infrastructure/index.html.erb <<'ERB'
<% content_for :title, "Gatekeeper Infrastructure" %>
<section style="max-width:1200px;margin:0 auto;padding:32px 20px;">
  <p>GATEKEEPER</p>
  <h1>Infrastructure Control</h1>
  <p>Nevaeh decides. Gatekeeper executes. Marlon handles the unknown.</p>

  <p>
    <%= link_to "Nodes", gatekeeper_nodes_path %> ·
    <%= link_to "Projects", gatekeeper_projects_path %> ·
    <%= link_to "Add Node", new_gatekeeper_node_path %> ·
    <%= link_to "Add Project", new_gatekeeper_project_path %>
  </p>

  <h2>Marlon Dependency</h2>
  <ul>
    <li>Operations: <%= @metrics[:operations] %></li>
    <li>Succeeded: <%= @metrics[:succeeded] %></li>
    <li>Failed: <%= @metrics[:failed] %></li>
    <li>Open escalations: <%= @metrics[:open_escalations] %></li>
    <li>Dependency rate: <%= number_to_percentage(@metrics[:marlon_dependency_rate] * 100, precision: 2) %></li>
  </ul>

  <h2>Nodes</h2>
  <% @nodes.each do |node| %>
    <p><%= link_to node.name, gatekeeper_node_path(node) %> — <%= node.status %> — <%= node.display_host %></p>
  <% end %>

  <h2>Open Escalations</h2>
  <% if @escalations.any? %>
    <% @escalations.each do |e| %><p><strong><%= e.category %></strong>: <%= e.reason %></p><% end %>
  <% else %>
    <p>Nothing requires your attention.</p>
  <% end %>

  <h2>Recent Operations</h2>
  <% @operations.each do |operation| %>
    <p><%= operation.capability %> — <%= operation.status %> — <%= operation.requested_by %></p>
  <% end %>
</section>
ERB

cat > app/views/gatekeeper/nodes/_form.html.erb <<'ERB'
<%= form_with model: [:gatekeeper, node] do |f| %>
  <% node.errors.full_messages.each { |message| concat(content_tag(:p, message)) } %>
  <p><%= f.label :name %><br><%= f.text_field :name, required: true %></p>
  <p><%= f.label :hostname %><br><%= f.text_field :hostname %></p>
  <p><%= f.label :ip_address %><br><%= f.text_field :ip_address, required: true %></p>
  <p><%= f.label :ssh_user %><br><%= f.text_field :ssh_user %></p>
  <p><%= f.label :ssh_port %><br><%= f.number_field :ssh_port %></p>
  <p><%= f.label :ssh_key_path %><br><%= f.text_field :ssh_key_path %></p>
  <p><%= f.label :provider %><br><%= f.text_field :provider %></p>
  <p><%= f.label :region %><br><%= f.text_field :region %></p>
  <%= f.submit %>
<% end %>
ERB

cat > app/views/gatekeeper/nodes/new.html.erb <<'ERB'
<h1>New Gatekeeper Node</h1>
<%= render "form", node: @node %>
ERB

cat > app/views/gatekeeper/nodes/edit.html.erb <<'ERB'
<h1>Edit Gatekeeper Node</h1>
<%= render "form", node: @node %>
ERB

cat > app/views/gatekeeper/nodes/index.html.erb <<'ERB'
<h1>Gatekeeper Nodes</h1>
<p><%= link_to "Infrastructure", gatekeeper_infrastructure_path %> · <%= link_to "New Node", new_gatekeeper_node_path %></p>
<% @nodes.each do |node| %>
  <p><%= link_to node.name, gatekeeper_node_path(node) %> — <%= node.status %> — <%= node.display_host %></p>
<% end %>
ERB

cat > app/views/gatekeeper/nodes/show.html.erb <<'ERB'
<h1><%= @node.name %></h1>
<p><%= @node.display_host %> · <%= @node.status %></p>
<p><%= link_to "Edit", edit_gatekeeper_node_path(@node) %> · <%= link_to "Add Project", new_gatekeeper_project_path(gatekeeper_node_id: @node.id) %></p>
<h2>Projects</h2>
<% @projects.each do |project| %>
  <p><%= link_to project.name, gatekeeper_project_path(project) %> — <%= project.status %></p>
<% end %>
ERB

cat > app/views/gatekeeper/projects/_form.html.erb <<'ERB'
<%= form_with model: [:gatekeeper, project] do |f| %>
  <% project.errors.full_messages.each { |message| concat(content_tag(:p, message)) } %>
  <p><%= f.label :gatekeeper_node_id, "Node" %><br><%= f.collection_select :gatekeeper_node_id, GatekeeperNode.order(:name), :id, :name %></p>
  <p><%= f.label :name %><br><%= f.text_field :name, required: true %></p>
  <p><%= f.label :repository %><br><%= f.text_field :repository, required: true %></p>
  <p><%= f.label :branch %><br><%= f.text_field :branch %></p>
  <p><%= f.label :domain %><br><%= f.text_field :domain, required: true %></p>
  <p><%= f.label :app_root %><br><%= f.text_field :app_root, required: true %></p>
  <p><%= f.label :app_user %><br><%= f.text_field :app_user %></p>
  <p><%= f.label :ruby_version %><br><%= f.text_field :ruby_version %></p>
  <p><%= f.label :sidekiq_service_name %><br><%= f.text_field :sidekiq_service_name %></p>
  <%= f.submit %>
<% end %>
ERB

cat > app/views/gatekeeper/projects/new.html.erb <<'ERB'
<h1>New Gatekeeper Project</h1>
<%= render "form", project: @project %>
ERB

cat > app/views/gatekeeper/projects/edit.html.erb <<'ERB'
<h1>Edit Gatekeeper Project</h1>
<%= render "form", project: @project %>
ERB

cat > app/views/gatekeeper/projects/index.html.erb <<'ERB'
<h1>Gatekeeper Projects</h1>
<p><%= link_to "Infrastructure", gatekeeper_infrastructure_path %> · <%= link_to "New Project", new_gatekeeper_project_path %></p>
<% @projects.each do |project| %>
  <p><%= link_to project.name, gatekeeper_project_path(project) %> — <%= project.status %> — <%= project.domain %></p>
<% end %>
ERB

cat > app/views/gatekeeper/projects/show.html.erb <<'ERB'
<h1><%= @project.name %></h1>
<p><%= @project.domain %> · <%= @project.status %></p>
<p><%= link_to "Edit", edit_gatekeeper_project_path(@project) %></p>
<p>
  <%= button_to "Deploy", deploy_gatekeeper_project_path(@project), method: :post %>
  <%= button_to "Healthcheck", healthcheck_gatekeeper_project_path(@project), method: :post %>
</p>
<h2>Recent Operations</h2>
<% @operations.each do |operation| %>
  <p><%= operation.capability %> — <%= operation.status %> — <%= operation.created_at %></p>
<% end %>
ERB

cat > lib/scripts/gatekeeper/deploy_project.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_USER:?APP_USER required}"
: "${APP_NAME:?APP_NAME required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"

APP_BRANCH="${APP_BRANCH:-main}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-${APP_NAME}-sidekiq}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
RUBY_BIN="/home/${APP_USER}/.rbenv/versions/${RUBY_VERSION}/bin"

[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -d "${APP_ROOT}/.git" ]] || { echo "ERROR: ${APP_ROOT} is not a git checkout"; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: missing ${ENV_FILE}"; exit 1; }

echo "[1/7] Pull"
git config --global --add safe.directory "${APP_ROOT}" >/dev/null 2>&1 || true
git -C "${APP_ROOT}" fetch origin "${APP_BRANCH}"
git -C "${APP_ROOT}" checkout "${APP_BRANCH}"
git -C "${APP_ROOT}" pull --ff-only origin "${APP_BRANCH}"

run_rails() {
  sudo -u "${APP_USER}" -H env -u GEM_HOME -u GEM_PATH bash -lc "
    set -a
    source '${ENV_FILE}'
    set +a
    export RBENV_ROOT='/home/${APP_USER}/.rbenv'
    export PATH='${RUBY_BIN}:/home/${APP_USER}/.rbenv/bin:/usr/local/bin:/usr/bin:/bin'
    cd '${APP_ROOT}'
    $*
  "
}

echo "[2/7] Bundle"
run_rails "bundle install --jobs 1"

echo "[3/7] Migrate"
run_rails "bundle exec rails db:migrate"

echo "[4/7] Assets"
run_rails "bundle exec rails assets:precompile"

echo "[5/7] Sidekiq"
systemctl restart "${SIDEKIQ_SERVICE}"
systemctl is-active --quiet "${SIDEKIQ_SERVICE}"

echo "[6/7] Apache"
apache2ctl configtest
systemctl reload "${APACHE_SERVICE}"
systemctl is-active --quiet "${APACHE_SERVICE}"

echo "[7/7] Health"
HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up")"
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: healthcheck HTTP ${HTTP_CODE}"; exit 1; }

SHA="$(git -C "${APP_ROOT}" rev-parse HEAD)"
echo "GATEKEEPER_DEPLOYED_SHA=${SHA}"
echo "GATEKEEPER_HTTP_STATUS=${HTTP_CODE}"
echo "DEPLOYMENT SUCCESSFUL"
BASH

cat > lib/scripts/gatekeeper/healthcheck_project.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"

APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-}"
FAILED=0

systemctl is-active --quiet "$APACHE_SERVICE" && echo "OK apache" || { echo "FAIL apache"; FAILED=1; }

if [[ -n "$SIDEKIQ_SERVICE" ]]; then
  systemctl is-active --quiet "$SIDEKIQ_SERVICE" && echo "OK sidekiq" || { echo "FAIL sidekiq"; FAILED=1; }
fi

passenger-status 2>/dev/null | grep -Fq "$APP_ROOT" && echo "OK passenger" || { echo "FAIL passenger"; FAILED=1; }

HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up" || true)"
[[ "$HTTP_CODE" == "200" ]] && echo "OK https 200" || { echo "FAIL https ${HTTP_CODE}"; FAILED=1; }

exit "$FAILED"
BASH

chmod +x lib/scripts/gatekeeper/*.sh

python3 - config/routes.rb <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

route_block = '''
# ── Gatekeeper Infrastructure Control ────────────────────────────────────────
namespace :gatekeeper do
  get "infrastructure", to: "infrastructure#index", as: :infrastructure
  resources :nodes
  resources :projects do
    member do
      post :deploy
      post :healthcheck
    end
  end
end

'''

if 'namespace :gatekeeper do' not in src:
    marker = '# ── Susu'
    pos = src.find(marker)
    if pos < 0:
        raise SystemExit("ERROR: could not find Susu route marker")
    src = src[:pos] + route_block + src[pos:]
    path.write_text(src)
    print("Added Gatekeeper infrastructure routes.")
else:
    print("Gatekeeper namespace already present; routes left unchanged.")
PY

cat > lib/tasks/gatekeeper_infrastructure.rake <<'RUBY'
namespace :gatekeeper do
  desc "Show Gatekeeper infrastructure and Marlon dependency status"
  task infrastructure_status: :environment do
    metrics = Gatekeeper::Metrics.summary

    puts "Nodes:                 #{GatekeeperNode.count}"
    puts "Projects:              #{GatekeeperProject.count}"
    puts "Operations:            #{metrics[:operations]}"
    puts "Succeeded:             #{metrics[:succeeded]}"
    puts "Failed:                #{metrics[:failed]}"
    puts "Open escalations:      #{metrics[:open_escalations]}"
    puts "Human interventions:   #{metrics[:human_interventions]}"
    puts format("Marlon dependency:    %.2f%%", metrics[:marlon_dependency_rate] * 100)
  end
end
RUBY

echo
echo "=== Syntax checks ==="
for file in \
  app/models/gatekeeper_node.rb \
  app/models/gatekeeper_project.rb \
  app/models/gatekeeper_operation.rb \
  app/models/gatekeeper_escalation.rb \
  app/services/gatekeeper/capability_registry.rb \
  app/services/gatekeeper/command_runner.rb \
  app/services/gatekeeper/executor.rb \
  app/services/gatekeeper/metrics.rb \
  app/services/gatekeeper/capabilities/deploy_project.rb \
  app/services/gatekeeper/capabilities/healthcheck_project.rb \
  app/jobs/gatekeeper/deploy_project_job.rb \
  app/jobs/gatekeeper/healthcheck_project_job.rb \
  app/controllers/gatekeeper/infrastructure_controller.rb \
  app/controllers/gatekeeper/nodes_controller.rb \
  app/controllers/gatekeeper/projects_controller.rb \
  "$MIGRATION"
do
  ruby -c "$file"
done

bash -n lib/scripts/gatekeeper/deploy_project.sh
bash -n lib/scripts/gatekeeper/healthcheck_project.sh
git diff --check

echo
echo "Gatekeeper Infrastructure Foundation installed."
echo "Backup: $BACKUP"
echo
echo "Next:"
echo "  bin/rails db:migrate"
echo "  bin/rails routes | grep gatekeeper"
echo "  bin/rails gatekeeper:infrastructure_status"
echo
echo "Dashboard:"
echo "  /gatekeeper/infrastructure"
