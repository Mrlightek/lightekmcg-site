namespace :gatekeeper do
  task learn_billable_execution: :environment do
    [
      {
        key: "GK-LESSON-LINODE-BILLABLE-EXECUTION",
        title: "Linode provisioning crosses a billable approval boundary",
        capability: "provision_compute_node",
        symptom: "An approved provisioning request is ready to create a real Linode.",
        cause: "Creating a Linode incurs provider charges, so discovery, pricing, approval, execution, registration and verification must remain separate audited stages.",
        remediation: "Discover types/regions/images first, store selected type/region/image and monthly estimate on ProvisioningRequest, require approval, create a GatekeeperOperation, generate the bootstrap credential into Lightek Vault, provision through LinodeAdapter, register the returned resource as GatekeeperNode, then verify provider state.",
        verification: "Linode ID, plan, region, IPs, GatekeeperNode, Vault credential reference and GatekeeperOperation are recorded; no secret value is logged.",
        metadata: { provider:"linode", billable:true, explicit_execution_required:true, auto_executable:false }
      },
      {
        key: "GK-LESSON-COMPUTE-DESTRUCTION-APPROVAL",
        title: "Provider node destruction requires a separate explicit approval",
        capability: "destroy_compute_node",
        symptom: "A managed provider node needs to be permanently deleted.",
        cause: "Destruction is irreversible and should not inherit approval from the original provisioning operation.",
        remediation: "Record destruction approval separately. Only after explicit destruction approval may Gatekeeper invoke provider deletion. Preserve GatekeeperNode as decommissioned audit history.",
        verification: "Provider delete succeeds, GatekeeperOperation succeeds, GatekeeperNode becomes decommissioned, and ProvisioningRequest records destroyed_at.",
        metadata: { destructive:true, separate_approval_required:true, auto_executable:false }
      }
    ].each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
