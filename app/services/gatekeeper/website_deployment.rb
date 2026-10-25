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
    CONSUMER = name.freeze
    class Invalid < StandardError; end

    def self.authorize!(actor)
      raise Invalid, "A super_admin operator is required" unless actor&.persisted? && actor.role == "super_admin"
    end

    def self.configuration(owner:, domain:, site_name:, headline:, description:, certificate_email:,
                           credential_slug:, internal: false, owner_email: nil)
      raise Invalid, "Owner must be a persisted User" unless owner.is_a?(User) && owner.persisted?
      host = domain.to_s.downcase.strip
      labels = host.split(".")
      raise Invalid, "A full hostname is required" unless labels.size >= 2 && host.size <= 253 &&
        labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }
      values = {"domain" => host, "owner_id" => owner.id, "site_name" => site_name.to_s,
        "headline" => headline.to_s, "description" => description.to_s,
        "email" => certificate_email.to_s, "credential_slug" => credential_slug.to_s,
        "owner_role" => internal ? "super_admin" : "admin"}
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
      config = record.metadata.to_h.fetch("website_deployments", {}).fetch(domain) {
        raise Invalid, "No deployment configuration is registered for this hostname"
      }.deep_dup
      owner = User.find(config.fetch("owner_id"))
      raise Invalid, "Internal owner is no longer super_admin" if config["owner_role"] == "super_admin" && owner.role != "super_admin"
      config.merge("owner_email" => config.fetch("owner_email", owner.email_address),
        "target" => record.is_a?(GatekeeperNode) ? "existing_node" : "new_instance",
        "node_id" => record.is_a?(GatekeeperNode) ? record.id : record.gatekeeper_node_id,
        "request_id" => record.is_a?(ProvisioningRequest) ? record.id : nil,
        "estimated_monthly_cost_cents" => record.is_a?(ProvisioningRequest) ? record.estimated_monthly_cost_cents : nil)
    end

    def self.run!(actor:, node:, domain:)
      authorize!(actor)
      new(actor:, node:, domain:).run!
    end

    def self.dns_environment(payload)
      values = payload.fetch("dns_env", {})
      raise Invalid, "Invalid DNS credential environment" unless values.is_a?(Hash) &&
        (values.keys - %w[GODADDY_PAT GODADDY_DOMAINS]).empty? &&
        values.values.all? { |v| v.is_a?(String) && !v.include?("\0") }
      values
    end

    # Allocation is permitted only through the existing approved request service.
    # A returned node remains bound to the request if deployment later fails.
    def self.provision_and_run!(actor:, request:, domain:)
      config = preview(actor:, record: request, domain:)
      raise Invalid, "Request owner differs from deployment owner" unless request.owner == User.find(config.fetch("owner_id"))
      # Validate the website credential before any provider allocation. This is
      # an audited checkout; preview itself remains free of secret reads.
      if request.gatekeeper_node_id.nil?
        raise Invalid, "Request is not approved and ready; no instance was created" unless request.executable?
        credential = nil
        begin
          credential = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"),
            consumer: CONSUMER, purpose: "website_deploy", requested_by: actor.email_address)
          raise Invalid, "Owner credential must have at least 8 characters" unless credential["owner_password"].is_a?(String) && credential["owner_password"].size >= 8
          dns_environment(credential)
        ensure
          credential&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
        end
      end
      node = nil
      request.with_lock do
        node = request.gatekeeper_node
        if node.nil?
          raise Invalid, "Request is not approved and ready; no instance was created" unless request.executable?
          node = Gatekeeper::Compute::ProvisioningExecutionService.call(request:, requested_by: actor.email_address)
        end
      end
      register!(actor:, record: node, config: config.slice("domain", "owner_id", "owner_email", "site_name", "headline", "description", "email", "credential_slug", "owner_role"))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 600
      loop do
        result = Gatekeeper::Compute::NodeVerificationService.call(request:, requested_by: actor.email_address)
        break if result[:provider_status] == "running"
        raise Invalid, "Instance is still starting; rerun uses the same node" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 10
      end
      run!(actor:, node:, domain:)
    end

    def initialize(actor:, node:, domain:)
      @actor, @node, @domain = actor, node, domain
    end

    def run!
      config = self.class.preview(actor: @actor, record: @node, domain: @domain)
      raise Invalid, "Only remote root SSH targets are supported by this installation path" if @node.local? || @node.ssh_user != "root"
      lock_root = Rails.root.join("tmp/lightek_deploy_locks")
      FileUtils.mkdir_p(lock_root, mode: 0o700)
      File.open(lock_root.join("node-#{@node.id}.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        raise Invalid, "A deployment is already running for this node" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        execute(config)
      end
    end

    def execute(config)
      operation = GatekeeperOperation.create!(gatekeeper_node: @node,
        capability: "deploy_website", requested_by: @actor.email_address,
        parameters: {domain: @domain, owner_id: config.fetch("owner_id"), owner_role: config.fetch("owner_role")},
        status: "running", started_at: Time.current)
      secrets = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"),
        consumer: CONSUMER, purpose: "website_deploy", requested_by: @actor.email_address,
        gatekeeper_operation_id: operation.id)
      password = secrets.fetch("owner_password")
      raise Invalid, "Owner credential must have at least 8 characters" unless password.is_a?(String) && password.size >= 8
      dns_env = self.class.dns_environment(secrets)
      root_secret = nil
      unless secrets["ssh_password"].present? || secrets["ssh_private_key"].present? || @node.ssh_key_path.present?
        slug = @node.metadata.to_h.fetch("node_credential_secret_slug") { raise Invalid, "No SSH credential is configured" }
        root_secret = LightekVault::Service.checkout!(slug:, consumer: CONSUMER, purpose: "node_bootstrap",
          requested_by: @actor.email_address, gatekeeper_operation_id: operation.id)
      end
      ssh_password = secrets["ssh_password"] || root_secret&.fetch("root_password")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
      loop do
        begin
          Socket.tcp(@node.ip_address, @node.ssh_port, connect_timeout: 5) { |socket| socket.close }
          break
        rescue SystemCallError, IOError, SocketError
          raise Invalid, "SSH is not ready; retry will use the same node" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          puts "Waiting for SSH on Gatekeeper node #{@node.id}..."
          sleep 5
        end
      end
      require "net/ssh"
      receipt = nil
      Dir.mktmpdir("lightek-deploy-") do |dir|
        File.chmod(0o700, dir)
        key = File.join(dir, "deployment-key")
        _, _, generated = Open3.capture3("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key)
        raise Invalid, "Could not generate temporary deployment SSH key" unless generated.success?
        public_key = File.read(key + ".pub").strip
        options = {port: @node.ssh_port, non_interactive: true, verify_host_key: :accept_new,
          timeout: 20, keepalive: true, keepalive_interval: 30}
        options[:password] = ssh_password if ssh_password.present?
        options[:key_data] = [secrets["ssh_private_key"]] if secrets["ssh_private_key"].present?
        options[:keys] = [@node.ssh_key_path] if @node.ssh_key_path.present?
        options[:auth_methods] = %w[publickey password keyboard-interactive]
        Net::SSH.start(@node.ip_address, @node.ssh_user, **options) do |ssh|
          installed = false
          begin
            command = "umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; printf '%s\\n' #{Shellwords.escape(public_key)} >> ~/.ssh/authorized_keys"
            ssh.exec!(command) { |_channel, _stream, _data| }
            installed = true
            input = config.slice("domain", "site_name", "headline", "description", "email", "owner_role", "owner_email")
            input.merge!("owner_password" => password, "ssh" => "root@#{@node.ip_address}",
              "port" => @node.ssh_port, "public_ip" => @node.ip_address, "ssh_key_path" => key)
            receipt = run_packager(input, dns_env:)
          ensure
            if installed
              cleanup = "from pathlib import Path; p=Path.home()/'.ssh/authorized_keys'; lines=p.read_text().splitlines(); p.write_text(''.join(s+'\\n' for s in lines if s.strip()!=#{public_key.inspect}))"
              begin
                ssh.exec!("python3 -c #{Shellwords.escape(cleanup)}")
              rescue StandardError
                Rails.logger.warn("[Lightek deployment] temporary SSH key cleanup needs attention for node #{@node.id}")
              end
            end
          end
        end
      end
      operation.update!(status: "succeeded", exit_status: 0, completed_at: Time.current, result: receipt)
      @node.with_lock do
        @node.update!(metadata: @node.metadata.to_h.merge("website_deployment" => receipt), status: "healthy")
      end
      {operation_id: operation.id, url: receipt.fetch("url"), verified: true}
    rescue StandardError => error
      if operation
        safe_error = Invalid.new("Website deployment failed (#{error.class.name}); inspect the deployment terminal and retry the same node")
        operation.update!(status: "failed", exit_status: 1, completed_at: Time.current,
          error_class: error.class.name, error_message: safe_error.message)
        begin
          articles = Gatekeeper::KnowledgeService.find_for_failure(operation:, error: safe_error)
          ticket = Gatekeeper::SupportTicketService.open_for_failure!(operation:, error: safe_error, knowledge_articles: articles)
          operation.update!(result: {support_ticket_id: ticket.id, support_ticket_number: ticket.number})
        rescue StandardError => ticket_error
          Rails.logger.warn("[Lightek deployment] ticket creation failed: #{ticket_error.class.name}")
        end
      end
      raise Invalid, "Website deployment failed (#{error.class.name}); operation #{operation&.id || 'not created'}"
    ensure
      [secrets, root_secret].compact.each { |payload| payload.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? } }
    end

    def run_packager(config, dns_env: {})
      receipt_path = nil
      passed = false
      Open3.popen2e({"RAILS_ENV" => Rails.env.to_s}.merge(dns_env), "bash", Rails.root.join("script/lightek/website_deploy.sh").to_s, "--config-stdin", chdir: Rails.root.to_s) do |stdin, output, thread|
        stdin.write(JSON.generate(config)); stdin.close
        output.each_line do |line|
          # Config/passwords are sent on stdin, never interpolated into commands.
          $stdout.print(line)
          passed = true if line.strip == "WEBSITE_DEPLOYMENT_PASS=https://#{@domain}"
          receipt_path = line.delete_prefix("Receipt: ").strip if line.start_with?("Receipt: ")
        end
        raise Invalid, "Packager did not pass acceptance" unless thread.value.success? && passed && receipt_path
      end
      path = Pathname.new(receipt_path).realpath
      expected = Rails.root.join("tmp/website_deploy").realpath
      raise Invalid, "Invalid deployment receipt path" unless path.parent == expected
      receipt = JSON.parse(path.read)
      raise Invalid, "Acceptance receipt is incomplete" unless receipt["url"] == "https://#{@domain}" &&
        receipt["public_https_verified"] == true && receipt["owner_login_verified"] == true
      receipt
    end
  end
end
