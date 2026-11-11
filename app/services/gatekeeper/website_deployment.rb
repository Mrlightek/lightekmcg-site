# frozen_string_literal: true
require "json"
require "open3"
require "tmpdir"
require "shellwords"
require "fileutils"
require "socket"

module Gatekeeper
  # Uses existing node/request records, Vault policy and operation receipts.
  class WebsiteDeployment
    extend WebsiteOwnerAccess
    CONSUMER = name.freeze
    class Invalid < StandardError; end

    def self.authorize!(actor)
      raise Invalid, "A super_admin operator is required" unless actor&.persisted? && actor.role == "super_admin"
    end

    def self.configuration(owner:, domain:, site_name:, headline:, description:, certificate_email:,
                           credential_slug:, internal: false, owner_email: nil)
      raise Invalid, "Owner must be a persisted User" unless owner.is_a?(User) && owner.persisted?
      
      host = begin
        LightekSettings::SiteDomain.public_hostname!(domain)
      rescue LightekSettings::SiteDomain::Invalid => error
        raise Invalid, error.message
      end

      values = {
        "domain" => host, 
        "owner_id" => owner.id, 
        "site_name" => site_name.to_s,
        "headline" => headline.to_s, 
        "description" => description.to_s,
        "email" => certificate_email.to_s, 
        "credential_slug" => credential_slug.to_s,
        "owner_role" => internal ? "super_admin" : "admin",
        "ssh" => "localhost"
      }

      raise Invalid, "Internal ownership requires a super_admin account" if internal && owner.role != "super_admin"
      if owner_email.present?
        email = owner_email.to_s.downcase.strip
        raise Invalid, "An owner email alias is supported only for internal deployments" unless internal || email == owner.email_address
        raise Invalid, "Invalid owner email" unless email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
        values["owner_email"] = email
      end
      raise Invalid, "Deployment values cannot be blank" if values.values.any? { |v| v.to_s.strip.empty? }
      raise Invalid, "Invalid certificate email" unless values["email"].match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
      raise Invalid, "Content exceeds maximum length" if %w[site_name headline description].any? { |key| values[key].size > 3000 }
      values
    end

    def self.register!(actor:, record:, config:)
      authorize!(actor)
      config = config.to_h.with_indifferent_access
      raise Invalid, "Unsupported deployment record" unless record.is_a?(GatekeeperNode) || record.is_a?(ProvisioningRequest)
      owner = User.find(config.fetch("owner_id"))
      if record.is_a?(ProvisioningRequest) && record.owner != owner
        raise Invalid, "Request owner differs from deployment owner"
      end
      record.with_lock do
        entries = record.metadata.to_h.fetch("website_deployments", {}).deep_dup
        previous = entries[config.fetch("domain")]
        raise Invalid, "Hostname already belongs to another owner" if previous && previous["owner_id"] != owner.id
        entries[config.fetch("domain")] = config
        record.update!(metadata: record.metadata.to_h.merge("website_deployments" => entries))
      end
      config.except("credential_slug")
    end

    def self.preview(actor:, record:, domain:)
      authorize!(actor)
      raw_config = record.metadata.to_h.fetch("website_deployments", {}).fetch(domain) {
        raise Invalid, "No deployment configuration is registered for this hostname"
      }
      config = raw_config.to_h.with_indifferent_access
      owner = User.find(config.fetch("owner_id"))
      raise Invalid, "Internal owner is no longer super_admin" if config["owner_role"] == "super_admin" && owner.role != "super_admin"
      config.merge("owner_email" => config.fetch("owner_email", owner.email_address),
        "target" => record.is_a?(GatekeeperNode) ? "existing_node" : "new_instance",
        "node_id" => record.is_a?(GatekeeperNode) ? record.id : record.gatekeeper_node_id,
        "request_id" => record.is_a?(ProvisioningRequest) ? record.id : nil,
        "estimated_monthly_cost_cents" => record.is_a?(ProvisioningRequest) ? record.estimated_monthly_cost_cents : nil).with_indifferent_access
    end

    def self.run!(actor:, node:, domain:)
      authorize!(actor)
      new(actor:, node:, domain:).run!
    end

    def self.provision_and_run!(actor:, request:, domain:)
      config = preview(actor:, record: request, domain:)
      raise Invalid, "Request owner differs from deployment owner" unless request.owner == User.find(config.fetch("owner_id"))
      if request.gatekeeper_node_id.nil?
        raise Invalid, "Request is not approved and ready; no instance was created" unless request.executable?
        credential = nil
        begin
          credential = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"),
            consumer: CONSUMER, purpose: "website_deploy", requested_by: actor.email_address)
          raise Invalid, "Owner credential must have at least 8 characters" unless credential["owner_password"].is_a?(String) && credential["owner_password"].size >= 8
          Gatekeeper::WebsiteDnsPublication.preflight!(hostname: domain)
        ensure
          credential&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
        end
      end
      node = request.reload.gatekeeper_node
      if node.nil?
        raise Invalid, "Request is not approved and ready; no instance was created" unless request.executable?
        node = Gatekeeper::Compute::ProvisioningExecutionService.call(request:, requested_by: actor.email_address)
      end
      begin
        Gatekeeper::Compute::NodeVerificationService.call(request:, requested_by: actor.email_address)
      rescue StandardError => e
        raise Invalid, "Provider node verification failed; reconcile the allocation before retrying (#{e.class})"
      end
      register!(actor:, record: node, config: config.slice("domain", "owner_id", "owner_email", "site_name", "headline", "description", "email", "credential_slug", "owner_role", "reservation_experience", "reservation_federation"))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 600
      loop do
        result = Gatekeeper::Compute::NodeVerificationService.call(request:, requested_by: actor.email_address)
        status = result[:provider_status].to_s
        break if status == "running"
        raise Invalid, "Linode entered terminal status #{status}; clean installation cannot continue" if %w[deleted deleting failed error].include?(status)
        remaining = (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).ceil
        raise Invalid, "Linode did not reach running within 600 seconds (last status: #{status})" if remaining <= 0
        puts "Waiting for Linode #{node.provider_resource_id}: status=#{status}, timeout_in=#{remaining}s"
        $stdout.flush
        sleep [10, remaining].min
      end
      Gatekeeper::WebsiteDnsPublication.call!(hostname: domain, ipv4: node.reload.ip_address)
      run!(actor:, node:, domain:)
    end

    def initialize(actor:, node:, domain:)
      @actor, @node, @domain = actor, node, domain
    end

    def run!
      config = self.class.preview(actor: @actor, record: @node, domain: @domain)
      raise Invalid, "Only remote root SSH targets are supported by this installation path" if !@node.local? && @node.ssh_user != "root"
      lock_root = Rails.root.join("tmp/lightek_deploy_locks")
      FileUtils.mkdir_p(lock_root, mode: 0o700)
      File.open(lock_root.join("node-#{@node.id}.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        raise Invalid, "A deployment is already running for this node" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        execute(config)
      end
    end

    def execute(config)
      config = config.to_h.with_indifferent_access
      peer_secrets = nil
      operation = GatekeeperOperation.create!(gatekeeper_node: @node,
        capability: "deploy_website", requested_by: @actor.email_address,
        parameters: {domain: @domain, owner_id: config.fetch("owner_id"), owner_role: config.fetch("owner_role")},
        status: "running", started_at: Time.current)

      if @node.metadata["local_node"] || @node.metadata[:local_node]
        @deployment_stage = "local_execution"
        receipt_path = nil
        passed = false
        Open3.popen2e({"RAILS_ENV" => Rails.env.to_s}, "bash", Rails.root.join("script/lightek/website_deploy.sh").to_s, "--config-stdin", chdir: Rails.root.to_s) do |stdin, output, wait_thr|
          stdin.write(JSON.generate(config))
          stdin.close
          output.each_line do |line|
            $stdout.print(line)
            passed = true if line.strip == "WEBSITE_DEPLOYMENT_PASS=https://#{@domain}"
            receipt_path = line.delete_prefix("Receipt: ").strip if line.start_with?("Receipt: ")
          end
          raise "Local deployment script failed with exit status #{wait_thr.value.exitstatus}" unless wait_thr.value.success? && passed && receipt_path
        end

        path = Pathname.new(receipt_path).realpath
        expected = Rails.root.join("tmp/website_deploy").realpath
        raise Invalid, "Invalid deployment receipt path" unless path.parent == expected
        receipt = JSON.parse(path.read)

        @deployment_stage = "inventory_sync"
        Gatekeeper::Fleet::Inventory.sync_node!(@node)
        operation.update!(status: "succeeded", result: receipt, exit_status: 0, completed_at: Time.current)
        return {operation_id: operation.id, url: receipt.fetch("url"), verified: true}
      end
    end
  end
end