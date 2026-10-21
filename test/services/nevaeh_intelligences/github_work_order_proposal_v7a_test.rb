# frozen_string_literal: true
require "test_helper"
require "json"

class GithubWorkOrderProposalV7aTest < ActiveSupport::TestCase
  FILE = Rails.root.join("config/project_tracking/lightek_studio.json")

  def setup
    @roadmap = JSON.parse(File.read(FILE))
    @item = @roadmap.fetch("items").find { |i| i["key"] == "STUDIO-203" }
    assert @item, "STUDIO-203 missing from canonical roadmap"
    @issue = {
      "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "number" => 46, "state" => "open",
      "title" => "[STUDIO-203] #{@item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"
    }
  end

  def test_maps_existing_issue_to_inert_work_order_proposal
    result = propose
    assert_equal "capability.build", result.fetch("work_type")
    assert_equal "github:Mrlightek/lightekmcg-site:STUDIO-203", result.fetch("intent_key")
    assert_equal @item.fetch("summary"), result.fetch("objective")
    assert_equal 46, result.fetch("inputs").fetch("source_number")
    assert_equal false, result.fetch("execution_policy").fetch("execution_enabled")
    assert_equal false, result.fetch("execution_policy").fetch("production_allowed")
    assert_equal true, result.fetch("execution_policy").fetch("requires_gatekeeper_authorization")
    assert_equal true, result.fetch("execution_policy").fetch("requires_human_release_approval")
  end

  def test_repeated_conversion_is_deterministic_and_immutable
    a = propose
    assert_equal a, propose
    assert_match(/\A[0-9a-f]{64}\z/, a.fetch("proposal_fingerprint"))
    assert_raises(FrozenError) { a.fetch("inputs")["source"] = "other" }
    assert_raises(FrozenError) { a.fetch("acceptance_criteria") << "extra" }
  end

  def test_rejects_tampered_contract
    normalized = NevaehIntelligences::GithubIssueContractV7a.from_issue(@issue, roadmap: @roadmap).dup
    normalized["objective"] = "new objective"
    assert_raises(NevaehIntelligences::GithubWorkOrderProposalV7a::ProposalError) do
      NevaehIntelligences::GithubWorkOrderProposalV7a.from_contract(normalized)
    end
  end

  def test_rejects_untrusted_issue_or_closed_issue
    @issue["state"] = "closed"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { propose }
    @issue["state"] = "open"
    @issue["html_url"] = "https://github.com/evil/repo/issues/46"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { propose }
  end

  def test_rejects_disabled_authorization_in_contract
    normalized = NevaehIntelligences::GithubIssueContractV7a.from_issue(@issue, roadmap: @roadmap).dup
    normalized["requires_authorization"] = false
    assert_raises(NevaehIntelligences::GithubWorkOrderProposalV7a::ProposalError) do
      NevaehIntelligences::GithubWorkOrderProposalV7a.from_contract(normalized)
    end
  end

  private

  def propose
    NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(@issue, roadmap: @roadmap)
  end
end
