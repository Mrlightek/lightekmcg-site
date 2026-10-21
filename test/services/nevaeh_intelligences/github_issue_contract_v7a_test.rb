# frozen_string_literal: true

require "test_helper"
require "json"

class GithubIssueContractV7aTest < ActiveSupport::TestCase
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

  def test_generates_deterministic_disabled_contract
    first = parse
    second = parse
    assert_equal first, second
    assert_equal "STUDIO-203", first.fetch("tracking_key")
    assert_equal @item.fetch("summary"), first.fetch("objective")
    assert_equal false, first.fetch("execution_enabled")
    assert_equal true, first.fetch("requires_authorization")
    assert_match(/\A[0-9a-f]{64}\z/, first.fetch("fingerprint"))
  end

  def test_rejects_untrusted_repository
    @issue["html_url"] = "https://github.com/other/repo/issues/46"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_missing_tracking_marker
    @issue["body"] = "not canonical"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_noncanonical_title
    @issue["title"] = "[STUDIO-203] Different feature"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_pull_requests
    @issue["pull_request"] = {}
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_closed_issues
    @issue["state"] = "closed"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_completed_roadmap_entries
    @item["status"] = "done"
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  def test_rejects_missing_roadmap_entry
    @roadmap["items"].reject! { |i| i["key"] == "STUDIO-203" }
    assert_raises(NevaehIntelligences::GithubIssueContractV7a::ContractError) { parse }
  end

  private

  def parse
    NevaehIntelligences::GithubIssueContractV7a.from_issue(@issue, roadmap: @roadmap)
  end
end
