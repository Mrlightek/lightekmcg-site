namespace :gatekeeper do
  desc "Register/update this Lightek production node and lightekmcg-site project"
  task bootstrap_production: :environment do
    node_name = ENV.fetch("GATEKEEPER_NODE_NAME", "lightekmcg-prod-01")
    node_ip = ENV.fetch("GATEKEEPER_NODE_IP", "127.0.0.1")
    node_hostname = ENV.fetch("GATEKEEPER_NODE_HOSTNAME", "lightekmcg.com")

    node = GatekeeperNode.find_or_initialize_by(name: node_name)
    node.assign_attributes(
      hostname: node_hostname,
      ip_address: node_ip,
      ssh_user: ENV.fetch("GATEKEEPER_NODE_SSH_USER", "root"),
      ssh_port: ENV.fetch("GATEKEEPER_NODE_SSH_PORT", "22").to_i,
      provider: ENV.fetch("GATEKEEPER_NODE_PROVIDER", "Linode"),
      region: ENV["GATEKEEPER_NODE_REGION"],
      status: node.status.presence || "unknown",
      metadata: node.metadata.to_h.merge(
        "role" => "production",
        "managed_by" => "gatekeeper",
        "local_node" => true
      )
    )
    node.save!

    project = GatekeeperProject.find_or_initialize_by(name: "lightekmcg-site")
    project.assign_attributes(
      gatekeeper_node: node,
      repository: ENV.fetch(
        "GATEKEEPER_PROJECT_REPOSITORY",
        "https://github.com/Mrlightek/lightekmcg-site.git"
      ),
      branch: ENV.fetch("GATEKEEPER_PROJECT_BRANCH", "main"),
      domain: ENV.fetch("GATEKEEPER_PROJECT_DOMAIN", "lightekmcg.com"),
      app_root: ENV.fetch("GATEKEEPER_PROJECT_ROOT", "/var/www/lightekmcg-site"),
      app_user: ENV.fetch("GATEKEEPER_PROJECT_USER", "lightek"),
      ruby_version: ENV.fetch("GATEKEEPER_PROJECT_RUBY", "3.3.6"),
      rails_env: "production",
      apache_service_name: ENV.fetch("GATEKEEPER_APACHE_SERVICE", "apache2"),
      sidekiq_service_name: ENV.fetch(
        "GATEKEEPER_SIDEKIQ_SERVICE",
        "lightekmcg-site-sidekiq"
      ),
      status: project.status.presence || "unknown",
      metadata: project.metadata.to_h.merge(
        "health_url" => "https://lightekmcg.com/up",
        "github_repository" => "Mrlightek/lightekmcg-site",
        "github_workflow" => "deploy-production.yml",
        "environment" => "production"
      )
    )
    project.save!

    puts "Gatekeeper production registration complete."
    puts "Node:    #{node.id} #{node.name} (#{node.display_host})"
    puts "Project: #{project.id} #{project.name} (#{project.domain})"
    puts "Status:  node=#{node.status} project=#{project.status}"
  end
end
