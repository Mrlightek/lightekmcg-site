namespace :gatekeeper do
  desc "Teach deployment warmup and provisioning approval boundary lessons"
  task learn_provisioning_orchestration: :environment do
    lessons = [
      {
        key: "GK-LESSON-POST-DEPLOY-HEALTH-WARMUP",
        title: "Post-deploy health checks tolerate bounded Passenger warm-up",
        capability: "deploy_project",
        symptom: "Immediately after Apache/Passenger reload, curl to /up times out with curl exit 28, while a later deployment or request succeeds.",
        cause: "The first health request can race Passenger/Rails cold startup even though Apache, migrations, assets and application boot are otherwise healthy.",
        remediation: "Retry the HTTPS /up health endpoint with bounded attempts, per-attempt timeout and sleep interval. Treat success on any bounded retry as healthy. Escalate only after all retries fail.",
        verification: "Deployment completes only after /up returns HTTP 200; persistent failures still exit nonzero.",
        metadata: {
          failure_signature: "curl: (28) Operation timed out",
          auto_executable: true,
          remediation: "bounded_health_retry"
        }
      },
      {
        key: "GK-LESSON-PROVISIONING-APPROVAL-BOUNDARY",
        title: "Subscriptions create provisioning requests before billable provider actions",
        capability: "provision_infrastructure",
        symptom: "An active subscription is entitled to dedicated infrastructure.",
        cause: "Directly turning subscription activation into provider API calls would mix billing entitlement, provider selection, cost authorization and destructive execution into one unsafe step.",
        remediation: "Resolve the subscription entitlement, create a durable ProvisioningRequest, select an eligible provider through ComputePolicy, require a known monthly cost, apply the automatic approval ceiling, and only mark the request ready when policy or a super administrator approves it. Provider execution is a separate later step.",
        verification: "The request records owner, plan, profile, policy, provider, node count, cost estimate, approval status and execution status before any billable provider API call occurs.",
        metadata: {
          auto_executable: false,
          billable_execution_separated: true,
          approval_boundary: "ProvisioningRequest"
        }
      }
    ]

    lessons.each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
