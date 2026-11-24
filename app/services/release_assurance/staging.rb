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
        details = Gatekeeper::Compute::StagingRequests.validate!(request)
        unless details["hostname"] == hostname && (request.estimated_monthly_cost_cents..details.fetch("budget_cents")).cover?(budget_cents)
          raise Policy::Denied, "Keep the attached hostname and budget within the prepared staging request"
        end
        expires_at = [hours.hours.from_now, Time.iso8601(details.fetch("expires_at"))].min
        environment = candidate.environments.build(provisioning_request: request, hostname: hostname,
          budget_cents: budget_cents, expires_at: expires_at)
        new(environment, actor).validate_request!
        environment.save!
        request.update!(metadata: Gatekeeper::Compute::StagingRequests.audit_metadata(request, actor, "attached to candidate #{candidate.id}"))
        environment
      end
    end

    def self.create_request!(actor:, hostname:, budget_cents:, hours:)
      Policy.runner!
      Gatekeeper::Compute::StagingRequests.prepare!(actor: actor, hostname: hostname, budget_cents: budget_cents, hours: hours)
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

    def publish_dns!(node)
      authorize_deployment!(actor: @actor, request: @request, domain: @hostname)
      raise Policy::Denied, "Staging node binding changed" unless @request.gatekeeper_node_id == node.id

      Gatekeeper::WebsiteDnsPublication.call!(hostname: @hostname, ipv4: node.ip_address, replace: false,
        expected_target: dns_target!) do |receipt|
        @request.with_lock do
          @request.update!(metadata: @request.metadata.to_h.merge("staging_dns_record" => receipt))
        end
      end
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

    def validate_request!(retiring: false)
      details = Gatekeeper::Compute::StagingRequests.validate!(@request, retiring: retiring)
      unless details["hostname"] == @hostname && @environment.budget_cents <= details.fetch("budget_cents") &&
          @environment.expires_at <= Time.iso8601(details.fetch("expires_at"))
        raise Policy::Denied, "The attached environment exceeds the prepared request"
      end

      config = Gatekeeper::WebsiteDeployment.preview(actor: @actor, record: @request, domain: @hostname)
      certificate_contact = config.fetch("email").to_s
      unless @request.owner_type == "User" && @request.owner_id == config.fetch("owner_id") &&
          config.fetch("owner_email").match?(/\Astaging-[a-z0-9-]+@example\.test\z/) &&
          config.fetch("owner_role") == "admin" && config.fetch("credential_slug") == details.fetch("vault").fetch("owner") &&
          config.keys.map(&:to_s).difference(%w[domain owner_id site_name headline description email credential_slug owner_role owner_email target node_id request_id]).empty? &&
          certificate_contact.present? &&
          @request.subscription_id.nil? && @request.requested_node_count == 1 &&
          @request.node_label == @hostname.split(".").first &&
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
      reason = error.is_a?(Policy::Denied) || error.is_a?(Gatekeeper::Compute::StagingRequests::Invalid) ? error.message : "Deployment halted (#{error.class.name})."
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
          validate_request!(retiring: true)
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
          @request.with_lock do
            @request.update!(execution_status: "cancelled",
              metadata: Gatekeeper::Compute::StagingRequests.audit_metadata(@request, @actor, "retired"))
          end
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
        @request.metadata.fetch("staging_provisioning").slice("zone", "vault"), config.except("node_id")]))
    end

    def preflight!
      catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: @request.compute_provider,
        requested_by: @actor.email_address, region: @request.selected_region,
        adapter: @request.compute_adapter(requested_by: @actor.email_address))
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

    def dns_target!
      details = @request.metadata.fetch("staging_provisioning")
      zone, name = Gatekeeper::WebsiteDnsPublication.target_for!(hostname: @hostname)
      raise Policy::Denied, "The approved staging DNS zone changed" unless zone == details.fetch("zone")

      legacy_slug = details.fetch("vault")["dns"]
      if legacy_slug && ENV["GODADDY_VAULT_SLUG"] != legacy_slug
        raise Policy::Denied, "Use the approved DNS Vault reference for this staging request"
      end
      [zone, name]
    end

    def staging_dns
      zone, name = dns_target!
      [Godaddy::DnsService.new(zone: zone), name]
    end

    def delete_dns!(ipv4)
      dns, name = staging_dns
      matching = dns.records.select { |record| record["name"].to_s.downcase == name && record["type"] == "A" }
      return if matching.empty?

      receipt = @request.metadata["staging_dns_record"]
      record = matching.first
      record_id = record["recordId"].presence || record["id"]
      unless matching.one? && receipt && record_id.present? && receipt["record_id"].to_s == record_id.to_s &&
          receipt["zone"] == dns_target!.first && receipt["name"] == name &&
          receipt["ipv4"] == ipv4.to_s && record["data"] == ipv4.to_s
        raise Policy::Denied, "Staging DNS record ownership could not be verified"
      end

      dns.delete_record!(record_id)
    end
  end
end
