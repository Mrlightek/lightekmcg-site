# frozen_string_literal: true

require "digest"

module ReleaseAssurance
  class Readiness
    SIMULATED_CI = %w[endpoint_fixtures commerce_fixtures remote_support_fixtures].freeze

    CI = {
      "application" => [".github/workflows/ci.yml", %w[test scan_ruby scan_js]],
      "staging_provisioning_dashboard" => [".github/workflows/staging-provisioning-dashboard.yml", %w[authenticated-dashboard]],
      "assurance_contracts" => [".github/workflows/batch-e-release-assurance.yml", %w[assurance-contracts]],
      "preflight" => [".github/workflows/deployment-preflight.yml", %w[release-operations]],
      "dashboard" => [".github/workflows/dashboard-appearance.yml", %w[appearance project-deletion]],
      "nevaeh" => [".github/workflows/nevaeh-control-center.yml", %w[graphical-workspace page-workers persistence-and-rendering]],
      "endpoint_fixtures" => [".github/workflows/it-device-agent.yml", [
        "debian-package-deployment", "rails-endpoints", "device-agent (ubuntu-latest)", "device-agent (macos-latest)", "device-agent (windows-latest)"
      ]],
      "commerce_fixtures" => [".github/workflows/it-services-business-acceptance.yml", %w[business-acceptance]],
      "remote_support_fixtures" => [".github/workflows/batch-d-acceptance.yml", [
        "desktop-relay-and-scan", "hosted-browser-codec (windows-latest)", "hosted-browser-codec (macos-latest)"
      ]]
    }.freeze

    SCENARIOS = {
      "windows_endpoint" => ["windows", "On a disposable Windows VM, install the selected native update through Gatekeeper. Verify the installed version and Dashboard receipt."],
      "macos_endpoint" => ["macos", "On a disposable macOS desktop, install the selected native update through Gatekeeper. Verify the installed version and Dashboard receipt."],
      "linux_endpoint" => ["linux", "On an isolated Linux VM, rehearse backup recovery against a synthetic database. Verify cutover, readback, and rollback without touching customer data."],
      "windows_remote" => ["windows", "On a disposable Windows desktop, verify attended capture, native input, consent revocation and the authorized unattended access lifecycle."],
      "macos_remote" => ["macos", "On a disposable macOS desktop, verify attended capture, native input, consent revocation and the authorized unattended access lifecycle."],
      "linux_remote" => ["linux", "On a disposable Linux desktop, verify the Dashboard support flow, consent, recording playback, and deployed TURN relay."],
      "commerce_staging" => [nil, "Use the synthetic customer and technician to verify booking to billing, sandbox payment, and sandbox payout receipts."],
      "browser_staging" => [nil, "In a browser, sign in as a synthetic account and complete the release's primary workflow. Confirm access stays within the assigned account."]
    }.freeze

    def initialize(candidate)
      @candidate = candidate
    end

    def required
      checks = (CI.keys - SIMULATED_CI).index_with("automated").merge(
        "staging" => "automated", "browser_smoke" => "automated", "browser_staging" => "real_world")
      return checks unless @candidate.profile == "msp"

      checks.merge(SIMULATED_CI.index_with("simulated")).merge(SCENARIOS.keys.index_with("real_world"))
    end

    def evaluation
      environment = @candidate.active_staging_environment
      runs = @candidate.runs.where(source_sha: @candidate.source_sha).where(environment_id: [nil, environment&.id])
        .order(id: :desc).to_a.group_by { |run| [run.check_key, run.kind] }

      blockers = []
      blockers << "Publish the reviewed source revision" unless @candidate.state == "published"
      blockers << "Deploy an active staging environment" unless environment
      if (workflow = @candidate.workflows.where(environment: environment, source_sha: @candidate.source_sha).order(id: :desc).first)
        blockers << "Acceptance refresh is still in progress" unless workflow.finished_at
        blockers << "Retry the failed acceptance refresh" if workflow.status == "failed"
      end
      verified_defects = @candidate.defects.where(status: "verified").select(:run_id)
      if @candidate.defects.exists?(status: "open") || @candidate.runs.where(result: "failed").where.not(id: verified_defects).exists?
        blockers << "Resolve failed checks and record retests"
      end
      evidence_ids = required.filter_map do |key, kind|
        run = runs[[key, kind]]&.first
        if run&.result == "passed"
          run.id
        else
          blockers << "#{key.humanize} — #{run&.result&.humanize || 'evidence missing'}"
          nil
        end
      end
      digest = Digest::SHA256.hexdigest(JSON.generate([@candidate.source_sha, environment&.id, evidence_ids]))
      {
        blockers: blockers, evidence_ids: evidence_ids, digest: digest,
        approved: blockers.empty? && @candidate.promotion_digest == digest && @candidate.promotion_approver&.role == "super_admin"
      }
    end

    def authorize_promotion!(actor, source_sha:)
      Policy.authorize!(actor, @candidate)
      @candidate.with_lock do
        result = evaluation
        raise Policy::Denied, "Production promotion lacks current approval for this revision" unless
          source_sha == @candidate.source_sha && result.fetch(:approved)
        result
      end
    end

    def approve!(actor, evidence_digest:)
      Policy.authorize!(actor, @candidate)
      @candidate.with_lock do
        result = evaluation
        raise Policy::Denied, "Resolve all release blockers before approving promotion" if result[:blockers].any?
        raise Policy::Denied, "Acceptance evidence changed" unless evidence_digest == result[:digest]
        @candidate.update!(promotion_approver: actor, promotion_approved_at: Time.current, promotion_digest: result.fetch(:digest))
      end
    end
  end
end
