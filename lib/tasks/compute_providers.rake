namespace :compute_providers do
  task seed: :environment do
    linode = ComputeProvider.find_or_initialize_by(slug: "linode")
    linode.assign_attributes(
      name: "Akamai / Linode", adapter_type: "builtin",
      adapter_class: "Gatekeeper::Compute::Providers::LinodeAdapter",
      api_base_url: "https://api.linode.com/v4",
      documentation_url: "https://techdocs.akamai.com/linode-api/reference/api",
      status: linode.status.presence || "draft",
      capabilities: %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(true),
      configuration: {}, metadata: linode.metadata.to_h.merge("builtin" => true)
    )
    linode.save!

    ovh = ComputeProvider.find_or_initialize_by(slug: "ovh")
    ovh.assign_attributes(
      name: "OVHcloud", adapter_type: "builtin",
      adapter_class: "Gatekeeper::Compute::Providers::OvhAdapter",
      documentation_url: "https://help.ovhcloud.com/",
      status: ovh.status.presence || "draft",
      capabilities: %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(false),
      configuration: { "endpoint" => "ovh-us", "endpoints" => {} },
      metadata: ovh.metadata.to_h.merge("builtin" => true, "note" => "Add service_name and endpoint mappings for the OVH product family Gatekeeper should manage.")
    )
    ovh.save!

    puts "Seeded #{linode.name} and #{ovh.name}"
  end

  task learn: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-COMPUTE-PROVIDER-CONTRACT",
      title: "Compute providers implement the Gatekeeper provider contract",
      capability: "compute_provider_onboarding",
      symptom: "Lightek needs to integrate a new infrastructure provider without coupling workflows to a vendor API.",
      cause: "Hard-coded provider calls leak vendor-specific logic into jobs, controllers, provisioning profiles, and customer workflows.",
      remediation: "Represent providers as ComputeProvider records. Store provider credentials only in Lightek Vault. Resolve builtin, declarative, or custom adapters through Gatekeeper::Compute::Registry. Validate read-only capabilities before any approved billable/destructive smoke test.",
      verification: "Provider is registered; Vault policy permits only its adapter; healthcheck passes; capability mappings are known; approved create/reboot/destroy test passes before activation.",
      metadata: { component: "gatekeeper_compute", adapter_types: %w[builtin declarative custom], credentials: "lightek_vault", auto_executable: false }
    )
    puts "Recorded GK-LESSON-COMPUTE-PROVIDER-CONTRACT as KB article #{article.id}"
  end
end
