namespace :infrastructure_catalog do
  task seed: :environment do
    [
      ["rails_shared","Rails Shared","shared_application",2,4096,80,%w[apache postgresql redis sidekiq],%w[22/tcp 80/tcp 443/tcp]],
      ["rails_dedicated","Rails Dedicated","dedicated_application",2,4096,80,%w[apache postgresql redis sidekiq],%w[22/tcp 80/tcp 443/tcp]],
      ["personal_cloud","Personal Cloud","personal_cloud",2,4096,80,%w[docker postgresql redis lightek_agent],%w[22/tcp 80/tcp 443/tcp]],
      ["mail_node","Mail Node","mail",2,4096,80,%w[postfix dovecot rspamd redis],%w[22/tcp 25/tcp 80/tcp 443/tcp 587/tcp 993/tcp]],
      ["worker_node","Worker Node","worker",2,4096,50,%w[redis sidekiq],%w[22/tcp]]
    ].each do |slug,name,purpose,cpu,memory,disk,services,rules|
      profile=ProvisioningProfile.find_or_initialize_by(slug:slug)
      profile.assign_attributes(name:name,purpose:purpose,os_image:"ubuntu-24.04",cpu_cores:cpu,memory_mb:memory,disk_gb:disk,services:services,firewall_rules:rules,active:true)
      profile.save!
      puts "Profile: #{profile.slug}"
    end

    linode=ComputeProvider.find_by(slug:"linode")
    ovh=ComputeProvider.find_by(slug:"ovh")

    [
      ["personal_cloud","Personal Cloud Policy","personal_cloud",ovh,linode,1000,700,%w[provision_node destroy_node]],
      ["lightek_production","Lightek Production Policy","production_application",linode,ovh,2500,1000,%w[provision_node reboot_node destroy_node]],
      ["mail","Mail Infrastructure Policy","mail",linode,ovh,2500,1000,%w[provision_node set_reverse_dns]]
    ].each do |slug,name,purpose,preferred,fallback,ceiling,auto,capabilities|
      policy=ComputePolicy.find_or_initialize_by(slug:slug)
      policy.assign_attributes(name:name,purpose:purpose,preferred_provider:preferred,fallback_provider:fallback,monthly_cost_ceiling_cents:ceiling,automatic_approval_ceiling_cents:auto,required_capabilities:capabilities,active:true)
      policy.save!
      puts "Policy: #{policy.slug}"
    end
  end

  task learn: :environment do
    a=Gatekeeper::LessonService.record!(
      key:"GK-LESSON-SUBSCRIPTION-INFRASTRUCTURE-ENTITLEMENTS",
      title:"Subscriptions map product entitlements to infrastructure policy",
      capability:"subscription_infrastructure_resolution",
      symptom:"A paid subscription needs to determine which services and infrastructure should be provisioned.",
      cause:"Billing plans and infrastructure were separate concepts, requiring humans to translate subscriptions into compute and service actions.",
      remediation:"Manage DymondBank SubscriptionPlan records through the dashboard and attach a SubscriptionInfrastructureEntitlement referencing a ProvisioningProfile, ComputePolicy, node quantity, features, and auto-provision behavior.",
      verification:"Resolve an active subscription through Gatekeeper::Compute::SubscriptionResolver and confirm its plan, profile, policy, node quantity and auto-provision setting.",
      metadata:{billing_system:"DymondBank",infrastructure_system:"Gatekeeper::Compute",auto_executable:false}
    )
    puts "Recorded lesson as KB article #{a.id}"
  end
end
