# frozen_string_literal: true

require "digest"
require "shellwords"
require "ipaddr"
require "open3"

module ReleaseAssurance
  class Staging
    def self.prepare!(candidate:, actor:, request:, hostname:, budget_cents:, hours:)
      Policy.authorize!(actor, candidate)
      Policy.runner!
      Policy.hostname!(hostname)
      raise Policy::Denied, "Publish the candidate first" unless candidate.state == "published"
      raise Policy::Denied, "Choose a positive budget and expiration of 4 to 168 hours" unless budget_cents.positive? && (4..168).cover?(hours)
      request.with_lock do
        raise Policy::Denied, "Use an unallocated request" if request.gatekeeper_node_id || request.gatekeeper_operation_id
        environment = candidate.environments.build(provisioning_request: request, hostname: hostname,
          budget_cents: budget_cents, expires_at: hours.hours.from_now)
        new(environment, actor).validate_request!
        environment.save!
        request.update!(metadata: request.metadata.to_h.merge("release_assurance_staging" => true))
        environment
      end
    end

    def self.create_request!(actor:, hostname:)
      Policy.authorize!(actor)
      Policy.runner!
      Policy.hostname!(hostname)
      owner = User.find_by!(email_address: ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_OWNER"))
      provider = ComputeProvider.find_by!(id: ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_PROVIDER_ID"), slug: "linode")
      region = ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_REGION")
      plan = ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_PLAN")
      catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: provider,
        requested_by: actor.email_address, region: region)
      entry = catalog.fetch("plans").find { |item| item["id"] == plan }
      raise Policy::Denied, "Configured staging plan has no price" unless entry && entry["monthly_cents"].to_i.positive?

      request = ProvisioningRequest.create!(owner: owner, compute_provider: provider, selected_region: region,
        selected_plan: plan, selected_image: "linode/ubuntu24.04", requested_node_count: 1,
        node_label: hostname.split(".").first, estimated_monthly_cost_cents: entry.fetch("monthly_cents"),
        execution_status: "awaiting_approval", approval_status: "pending",
        metadata: { "requested_by" => actor.email_address, "release_assurance_staging" => true })
      deployment = Gatekeeper::WebsiteDeployment
      config = deployment.configuration(owner: owner, domain: hostname, site_name: "Lightek staging",
        headline: "Release acceptance", description: "Synthetic acceptance tenant",
        certificate_email: ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_CERTIFICATE_EMAIL"),
        credential_slug: ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_OWNER_VAULT"))
      deployment.register!(actor: actor, record: request, config: config)
      request
    rescue KeyError
      raise Policy::Denied, "Configure the staging owner, provider, region, plan, Vault reference and certificate contact"
    end

    def initialize(environment, actor)
      @environment, @actor = environment, actor
      @candidate = environment.candidate
      @request = environment.provisioning_request
      @hostname = environment.hostname
    end

    def approve!
      authorize!
      @environment.with_lock do
        raise Policy::Denied, "Only a prepared staging target can be approved" unless @environment.state == "prepared"
        raise Policy::Denied, "First approve the request through Gatekeeper" unless @request.reload.executable? && @request.approval_status == "approved"
        validate_request!
        @environment.update!(state: "approved", approval_digest: binding)
      end
      DeploymentJob.perform_later(@environment.id)
    end

    attr_reader :source_root

    def source_sha = @candidate.source_sha
    def beta_key = BetaAccess.key_for(@environment)

    def authorize_compute!(request)
      authorize_deployment!(actor: @actor, request: request, domain: @hostname)
    end

    def authorize_deployment!(actor:, request:, domain:)
      authorize!
      raise Policy::Denied, "Staging deployment binding changed" unless actor == @actor && request == @request &&
        domain == @hostname && @source_root && @environment.reload.state == "deploying" &&
        @environment.approval_digest == binding
    end

    def configure_host!(ssh)
      script = Rails.root.join("script/lightek/release_assurance_host.sh").read
      arguments = [@hostname, source_sha, @candidate.profile, *@test_networks]
      channel = ssh.open_channel do |connection|
        connection.exec("bash -s -- #{Shellwords.join(arguments)}") do |process, accepted|
          raise Policy::Denied, "Could not start staging host configuration" unless accepted

          process.on_request("exit-status") { |_ch, data| @host_exit = data.read_long }
          process.send_data(script)
          process.eof!
        end
      end
      channel.wait
      raise Policy::Denied, "Staging firewall or host services failed" unless @host_exit == 0
    end

    def validate_request!
      config = Gatekeeper::WebsiteDeployment.preview(actor: @actor, record: @request, domain: @hostname)
      certificate_contact = config.fetch("email").to_s
      unless @request.owner_type == "User" && @request.owner_id == config.fetch("owner_id") &&
          config.fetch("owner_email").match?(/\Astaging-[a-z0-9-]+@example\.test\z/) &&
          config.fetch("owner_role") == "admin" && config.fetch("credential_slug").start_with?("staging-") &&
          config.keys.map(&:to_s).difference(%w[domain owner_id site_name headline description email credential_slug owner_role owner_email target node_id request_id]).empty? &&
          certificate_contact.present? &&
          @request.subscription_id.nil? && @request.requested_node_count == 1 &&
          @request.node_label == @hostname.split(".").first && @request.compute_provider&.slug == "linode" &&
          @request.selected_image == "linode/ubuntu24.04"
        raise Policy::Denied, "Use a dedicated Ubuntu 24.04 request with a synthetic owner and staging-only Vault configuration"
      end
      config
    end

    def deploy!
      authorize!
      @environment.with_lock do
        return unless @environment.state == "approved"
        raise Policy::Denied, "Staging approval or request binding changed" unless @environment.approval_digest == binding && @request.reload.executable? && @request.approval_status == "approved"
        @environment.update!(state: "deploying")
      end
      preflight!
      Source.new.checkout(@candidate.source_sha, @candidate.publication_ref) do |root|
        @source_root = root
        Bundler.with_unbundled_env do
          _, _, dependencies = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
            "bundle", "check", chdir: root)
          raise Policy::Denied, "Install the candidate's pinned private dependencies on the staging runner" unless dependencies.success?
        end
        result = Gatekeeper::WebsiteDeployment.provision_and_run!(actor: @actor, request: @request,
          domain: @hostname, staging: self)
        operation = GatekeeperOperation.find(result.fetch(:operation_id))
        raise Policy::Denied, "Gatekeeper returned a different deployed revision" unless operation.result.fetch("source_sha") == @candidate.source_sha
        @environment.update!(deployment_operation: operation)
        @candidate.with_lock do
          @environment.update!(state: "ready", failure: nil)
          @candidate.runs.create!(environment: @environment, check_key: "staging",
            kind: "automated", result: "passed", source_sha: @candidate.source_sha,
            evidence: { "operation_id" => operation.id })
        end
      end
      BrowserJob.perform_later(@environment.id)
    rescue StandardError => error
      reason = error.is_a?(Policy::Denied) ? error.message : "Deployment halted (#{error.class.name})."
      @environment.update!(state: "failed", failure: reason)
      Rails.logger.warn("[Release Assurance] staging=#{@environment.id} error=#{error.class.name}")
    end

    def queue_retirement!
      Policy.authorize!(@actor, @candidate)
      Policy.runner!
      @environment.with_lock do
        raise Policy::Denied, "Deployment is in progress" if @environment.state == "deploying"
        return if @environment.state == "retired"

        @environment.update!(state: "retiring")
      end
      ExpirationJob.perform_later
    end

    def retire!
      Policy.authorize!(@actor, @candidate)
      Policy.runner!
      Policy.hostname!(@hostname)
      @environment.with_lock do
        return if @environment.state == "retired"
        raise Policy::Denied, "Deployment is in progress" if @environment.state == "deploying"
        @request.reload
        if @request.gatekeeper_node.nil? && @request.gatekeeper_operation_id && @request.execution_status != "cancelled"
          raise Policy::Denied, "Reconcile the uncertain provider allocation through Gatekeeper"
        end
        if @request.gatekeeper_node
          validate_request!
          node = @request.gatekeeper_node
          raise Policy::Denied, "Staging server binding has changed" unless
            node.owner == @request.owner && node.compute_provider_id == @request.compute_provider_id &&
            node.name == @request.node_label && node.ip_address.present? && !node.local?
          if @request.metadata.to_h["delete_state"] != "queued" && !@request.destroyed_at
            Gatekeeper::Hosting::Deletions.request!(actor: @actor, node: node, confirmation: node.name)
          end
          @request.reload
          if @request.destroyed_at
            delete_dns!(node.ip_address)
            @environment.update!(state: "retired")
          else
            @environment.update!(state: "retiring")
          end
        else
          @environment.update!(state: "retired")
        end
      end
    end

    private

    def authorize!
      Policy.authorize!(@actor, @candidate)
      Policy.runner!
      Policy.hostname!(@hostname)
      raise Policy::Denied, "Staging approval expired" unless @environment.expires_at.future?
    end

    def binding
      @request.reload
      config = validate_request!
      Digest::SHA256.hexdigest(JSON.generate([@candidate.source_sha, @hostname, @environment.budget_cents,
        @environment.expires_at.to_i, @request.id, @request.owner_id, @request.compute_provider_id,
        @request.selected_region, @request.selected_plan, @request.selected_image, @request.approved_at&.to_i,
        config.except("node_id")]))
    end

    def preflight!
      catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: @request.compute_provider,
        requested_by: @actor.email_address, region: @request.selected_region)
      plan = catalog.fetch("plans").find { |entry| entry.fetch("id") == @request.selected_plan }
      unless plan && plan["monthly_cents"].to_i.positive? && plan["monthly_cents"] <= @environment.budget_cents &&
          plan["monthly_cents"] <= @request.estimated_monthly_cost_cents.to_i &&
          (2..8).cover?(plan["vcpus"]) && (4096..16_384).cover?(plan["memory"]) &&
          (65_536..327_680).cover?(plan["disk"])
        raise Policy::Denied, "Live pricing or resources exceed the staging approval"
      end
      dns, name = staging_dns
      raise Policy::Denied, "Staging hostname already has DNS records" if dns.records.any? { |record| record["name"].to_s.downcase == name }
      networks = ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_TEST_NETWORKS", "").split(",")
      raise Policy::Denied, "Configure scoped tester IPv4 CIDRs on the staging runner" if networks.empty?
      @test_networks = networks.map do |cidr|
        network = IPAddr.new(cidr)
        raise Policy::Denied, "Tester networks must be scoped IPv4 CIDRs" unless network.ipv4? && cidr.match?(/\A[0-9.]+\/[0-9]{1,2}\z/) && (8..32).cover?(network.prefix)
        "#{network}/#{network.prefix}"
      end
    end

    def staging_dns
      dns, name = Gatekeeper::WebsiteDnsPublication.service_for!(hostname: @hostname)
      raise Policy::Denied, "Use a dedicated authoritative staging DNS zone" unless name == @hostname.split(".").first
      [dns, name]
    end

    def delete_dns!(ipv4)
      dns, name = staging_dns
      matching = dns.records.select { |record| record["name"].to_s.downcase == name && record["type"] == "A" }
      return if matching.empty?
      raise Policy::Denied, "Staging DNS binding changed" unless matching.one? && matching.first["data"] == ipv4.to_s
      dns.delete_record!(matching.first["recordId"].presence || matching.first.fetch("id"))
    end
  end
end
