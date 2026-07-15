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
