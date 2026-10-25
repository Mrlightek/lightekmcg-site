require "test_helper"
class LightekDesignStudioDocumentTest < ActiveSupport::TestCase
  def actor(id = 8101, role = "admin") = Struct.new(:id, :role).new(id, role)
  def workspace(user = actor, source = nil)
    LightekDesign::StudioDocument.create!(user: user, name: "Client design", source: source)
  end
  def document(record) = LightekDesign::StudioDocument.draft(record)
  def publish(record)
    LightekDesign::StudioDocument.publish!(record: record, document: document(record), expected_revision: LightekDesign::StudioDocument.revision(record))
  end
  setup { LightekDesign::StudioContext.reset }
  teardown { LightekDesign::StudioContext.reset }

  test "deleting a workspace preserves its releases client pages and template snapshot" do
    record = workspace
    release = publish(record)
    site = DymondSite::Site.create!(name: "Delete isolation", host: "delete-#{SecureRandom.hex(6)}.example.test")
    page = LightekDesign::WebsiteDesigns.import!(site: site, design: release.key)
    LightekDesign::WebsiteDesigns.apply!(site: site, design: release.key)
    snapshot = site.reload.active_template.settings.deep_dup
    sections = page.sections.map { |section| section.attributes }
    LightekDesign::StudioDocument.destroy!(record: record, user: actor, expected_revision: 2)
    refute DymondSite::SiteTemplate.exists?(record.id)
    assert DymondSite::SiteTemplate.exists?(release.id)
    assert_equal snapshot, site.reload.active_template.settings
    assert_equal sections, page.reload.sections.map { |section| section.attributes }
    assert_equal "Client design", LightekDesign::Catalog.fetch(release.key)["name"]
  end
  test "deletion rejects another owner and stale revisions while super admin can delete" do
    record = workspace
    assert_raises(ActiveRecord::RecordNotFound) do
      LightekDesign::StudioDocument.destroy!(record: record, user: actor(8202), expected_revision: 1)
    end
    LightekDesign::StudioDocument.update!(record: record, document: document(record).merge("name" => "New work"), expected_revision: 1)
    assert_raises(LightekDesign::StudioDocument::Conflict) do
      LightekDesign::StudioDocument.destroy!(record: record, user: actor, expected_revision: 1)
    end
    assert_equal "New work", document(record.reload)["name"]
    LightekDesign::StudioDocument.destroy!(record: record, user: actor(8303, "super_admin"), expected_revision: 2)
    refute DymondSite::SiteTemplate.exists?(record.id)
  end
  test "a directly assigned workspace cannot be deleted" do
    record = workspace
    DymondSite::Site.create!(name: "Direct assignment", host: "direct-#{SecureRandom.hex(6)}.example.test", active_template_id: record.id)
    assert_raises(ArgumentError) do
      LightekDesign::StudioDocument.destroy!(record: record, user: actor, expected_revision: 1)
    end
    assert DymondSite::SiteTemplate.exists?(record.id)
  end

  test "blank designs are saved as owned drafts without changing websites" do
    record = workspace
    assert_equal 4, document(record)["sections"].length
    assert_equal "Client design", document(record)["name"]
    assert_equal 1, LightekDesign::StudioDocument.revision(record)
    assert_empty LightekDesign::Catalog.selectable_designs(user: actor).keys.grep(/^ld_release_/)
    assert_equal record.id, LightekDesign::StudioDocument.find_for!(record.id, actor).id
  end
  test "design workspaces enforce ownership with super admin access" do
    record = workspace
    assert_raises(ActiveRecord::RecordNotFound) { LightekDesign::StudioDocument.find_for!(record.id, actor(8202)) }
    assert_equal record.id, LightekDesign::StudioDocument.find_for!(record.id, actor(8303, "super_admin")).id
    assert_empty LightekDesign::StudioDocument.documents_for(actor(8202))
  end
  test "saving uses a revision check so concurrent edits are preserved" do
    record = workspace
    stale = DymondSite::SiteTemplate.find(record.id)
    revised = document(record).merge("name" => "Saved from first tab")
    LightekDesign::StudioDocument.update!(record: record, document: revised, expected_revision: 1)
    assert_raises(LightekDesign::StudioDocument::Conflict) do
      LightekDesign::StudioDocument.update!(record: stale, document: document(stale).merge("name" => "Stale copy"), expected_revision: 1)
    end
    assert_equal "Saved from first tab", document(record.reload)["name"]
    assert_equal 2, LightekDesign::StudioDocument.revision(record)
  end
  test "invalid styles fonts section IDs and section types never persist" do
    record = workspace
    original = record.settings.deep_dup
    invalid = document(record); invalid["sections"][0]["style"]["background"] = "red;}</style><script>"
    assert_raises(ArgumentError) { LightekDesign::StudioDocument.update!(record: record, document: invalid, expected_revision: 1) }
    invalid = document(record); invalid["fonts"]["font_heading"] = "url(javascript:alert(1))"
    assert_raises(ArgumentError) { LightekDesign::StudioDocument.normalize(invalid) }
    invalid = document(record); invalid["sections"][1]["id"] = invalid["sections"][0]["id"]
    assert_raises(ArgumentError) { LightekDesign::StudioDocument.normalize(invalid) }
    invalid = document(record); invalid["sections"][0]["block"] = "../../layouts/application"
    assert_raises(ArgumentError) { LightekDesign::StudioDocument.normalize(invalid) }
    assert_equal original, record.reload.settings
  end
  test "publishing generates registered editable sections and an unpublished starter" do
    record = workspace
    release = publish(record)
    definition = LightekDesign::Catalog.fetch(release.key)
    assert definition["designer"]
    assert_equal 1, definition["version"]
    definition["sections"].each do |entry|
      klass = DymondSite::SectionRegistry.find(entry["kind"])
      assert klass
      assert_equal "lightek_designer", klass.template
      assert_equal entry["fields"].map { |field| field["name"] }.sort, klass.schema.map { |field| field[:name].to_s }.sort
    end
    site = DymondSite::Site.create!(name: "Design client", host: "studio-#{SecureRandom.hex(6)}.example.test")
    page = LightekDesign::WebsiteDesigns.import!(site: site, design: release.key)
    assert_equal 4, page.sections.count
    refute page.published?
    assert_nil site.reload.active_template_id
    LightekDesign::WebsiteDesigns.apply!(site: site, design: release.key)
    assert_equal release.key, LightekDesign::Catalog.design_for(site.reload)
    assert_equal page.id, LightekDesign::WebsiteDesigns.import!(site: site, design: release.key).id
  end
  test "an active website copy carries its immutable design definition" do
    record = workspace
    release = publish(record)
    site = DymondSite::Site.create!(name: "Portable client", host: "portable-#{SecureRandom.hex(6)}.example.test")
    LightekDesign::WebsiteDesigns.apply!(site: site, design: release.key)
    assert_equal release.settings["lightek_studio_release"], site.reload.active_template.settings["lightek_studio_snapshot"]
    release.destroy!
    LightekDesign::StudioContext.reset
    assert_equal "Client design", LightekDesign::Catalog.fetch(site.active_template.settings["lightek_design"])["name"]
  end

  test "releasing unchanged content reuses the same library version" do
    record = workspace
    first = publish(record)
    revision = LightekDesign::StudioDocument.revision(record)
    assert_no_difference "DymondSite::SiteTemplate.count" do
      assert_equal first.id, publish(record).id
    end
    assert_equal revision, LightekDesign::StudioDocument.revision(record.reload)
  end

  test "new releases leave old releases and client edits unchanged" do
    record = workspace
    first = publish(record)
    frozen_definition = first.settings.deep_dup
    revised = document(record); revised["sections"][0]["data"]["heading"] = "Updated library version"
    second = LightekDesign::StudioDocument.publish!(record: record, document: revised, expected_revision: 2)
    refute_equal first.key, second.key
    assert_equal frozen_definition, first.reload.settings
    assert_equal 2, second.settings.dig("lightek_studio_release", "version")
    list = LightekDesign::Catalog.selectable_designs(user: actor)
    refute list.key?(first.key)
    assert list.key?(second.key)
    assert LightekDesign::Catalog.selectable_designs(user: actor, active: first.key).key?(first.key)
  end
  test "library designs are scoped and cloning another owner's release is denied" do
    record = workspace
    release = publish(record)
    assert LightekDesign::Catalog.selectable_designs(user: actor).key?(release.key)
    refute LightekDesign::Catalog.selectable_designs(user: actor(8202)).key?(release.key)
    assert LightekDesign::Catalog.selectable_designs(user: actor(8303, "super_admin")).key?(release.key)
    assert_raises(ActiveRecord::RecordNotFound) { workspace(actor(8202), release.key) }
    cloned = workspace(actor, release.key)
    assert_equal 4, document(cloned)["sections"].length
    refute_equal document(record)["sections"][0]["id"], document(cloned)["sections"][0]["id"]
  end
  test "VinylCTRL and YBNC clone as editable drafts with source layouts preserved" do
    %w[vinylctrl ybnc].each do |key|
      record = workspace(actor, key)
      draft = document(record)
      assert_equal LightekDesign::Catalog.builtin_designs[key]["sections"].length, draft["sections"].length
      assert_equal key, draft["base_design"]
      assert draft["sections"].all? { |section| section["source_kind"].start_with?(key) && section["style"]["padding"] == 0 }
      release = publish(record)
      assert LightekDesign::Catalog.fetch(release.key)["sections"].last["chrome_footer"]
    end
  end
end
