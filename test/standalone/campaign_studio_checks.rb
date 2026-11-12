require_relative "studio_production_checks"
require File.join(ROOT, "db/migrate/20261028173000_create_lightek_marketing_campaigns")
CreateLightekMarketingCampaigns.new.migrate(:up)
ActiveRecord::Schema.define do
  add_column :lightek_marketing_campaigns, :media_url, :string
  create_table(:lightek_agency_site_memberships) { |t| t.references :site; t.references :user; t.references :granted_by; t.string :role }
end
%w[app/models/lightek_marketing/campaign app/models/lightek_agency/site_membership app/services/lightek_settings/website_identity app/services/lightek_agency/access app/services/lightek_marketing/studio_production].each { |name| require File.join(ROOT, name) }
require File.join(ROOT, "app/controllers/dashboard/commerce_base_controller")
require File.join(ROOT, "app/controllers/dashboard/marketing_campaigns_controller")
require File.join(ROOT, "app/services/studio/editors/document")
require File.join(ROOT, "app/services/studio/editors/export")
require File.join(ROOT, "app/controllers/dashboard/studio_editors_controller")
Dashboard::StudioEditorsController.prepend_view_path(File.join(ROOT,"app/views"))
Dashboard::StudioEditorsController.layout false
Rails.application.routes.draw do
  # Use Rails' real blob redirect/disk routes for editor media acceptance.
  storage_routes = File.read(ActiveStorage::Engine.root.join("config/routes.rb"))
  storage_routes = storage_routes.sub(/.*?Rails\.application\.routes\.draw do/m, "").sub(/end if ActiveStorage\.draw_routes\s*\z/, "")
  instance_eval(storage_routes, "active_storage_routes.rb")
  scope "/dashboard/studio/editors/:kind", controller: "dashboard/studio_editors", as: :dashboard_studio_editor do
    get "/new", action: :new, as: :new
    post "/", action: :create, as: :create
    get "/:id", action: :show, as: ""
    put "/:id/document", action: :save, as: :document
    post "/:id/media", action: :media, as: :media
    post "/:id/export", action: :export, as: :export
    get "/:id/exports/:operation_id", action: :status, as: :status
  end
  post "/dashboard/studio-broadcasting/execute", to: "dashboard/media_studio#workspace_execute"
  post "/dashboard/studio-broadcasting/uploads", to: "dashboard/media_studio#workspace_upload"
  get "/dashboard/studio-broadcasting/assets/:id/:flavor", to: "dashboard/media_studio#workspace_asset"
  post "/dashboard/marketing/campaigns/:id/studio", to: "dashboard/marketing_campaigns#studio", as: :studio_dashboard_marketing_campaign
  get "/dashboard/marketing/campaigns/:id/edit", to: "dashboard/marketing_campaigns#edit", as: :edit_dashboard_marketing_campaign
end

class CampaignStudioChecks < StudioProductionTest
  StudioProductionTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @alice.update!(role: "admin")
    @site.update!(tenant: @alice)
    @campaign = LightekMarketing::Campaign.create!(site: @site, name: "Launch", channel: "social", headline: "Our new collection", message: "Meet the makers", cta_label: "Shop now", cta_url: "https://lightek.test/shop")
  end
  def open_studio(actor = @alice) = LightekMarketing::StudioProduction.open!(campaign: @campaign, actor: actor)
  def test_campaign_creates_portrait_production_with_editable_brief_and_idempotent_reopening
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    scene = open_studio
    assert_equal @site.id, scene.studio_project.site_id
    assert_equal @alice.id, scene.studio_project.owner_id
    assert_equal [1080, 1920], scene.settings.fetch("timeline").values_at("width", "height")
    assert_equal @campaign.id, scene.settings["campaign_id"]
    assert_includes scene.settings.dig("workspace", "story", "scriptDraft"), "Meet the makers"
    assert_includes scene.settings.dig("workspace", "story", "scriptDraft"), "https://lightek.test/shop"
    settings = scene.settings.deep_dup
    settings["workspace"]["story"]["scriptDraft"] = "My edited script"
    scene.update!(settings: settings)
    @campaign.update!(headline: "New campaign headline")
    before_count = StudioProject.count
    assert_equal scene.id, open_studio.id
    assert_equal before_count, StudioProject.count
    assert_equal "My edited script", scene.reload.settings.dig("workspace", "story", "scriptDraft")
    assert_equal queued, ActiveJob::Base.queue_adapter.enqueued_jobs.size
  end
  def test_foreign_account_cannot_create_or_read_campaign_production
    @bob.update!(role: "admin")
    before = StudioProject.count
    assert_raises(ActiveRecord::RecordNotFound) { open_studio(@bob) }
    assert_equal before, StudioProject.count
  end
  def test_marketer_can_see_campaign_but_cannot_author_studio_and_designer_has_separate_editable_project
    @bob.update!(role: "admin")
    membership = LightekAgency::SiteMembership.create!(site: @site, user: @bob, granted_by: @alice, role: "marketer")
    assert_raises(LightekPwa::Policy::Denied) { open_studio(@bob) }
    membership.update!(role: "designer")
    owner_scene = open_studio
    collaborator_scene = open_studio(@bob)
    refute_equal owner_scene.id, collaborator_scene.id
    assert_equal @bob.id, collaborator_scene.studio_project.owner_id
  end
  def test_non_social_campaign_starts_landscape
    @campaign.update!(channel: "email")
    assert_equal [1920, 1080], open_studio.settings.fetch("timeline").values_at("width", "height")
  end
  def test_campaign_studio_http_requires_csrf_preserves_site_and_opens_real_native_workspace
    Dashboard::MarketingCampaignsController.allow_forgery_protection = true
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! "lightek.test"
    client.get "/test/csrf", headers: headers
    token = JSON.parse(client.response.body).fetch("csrf_token")
    url = "/dashboard/marketing/campaigns/#{@campaign.id}/studio?site_id=#{@site.id}"
    client.post url, headers: headers.merge("X-CSRF-Token" => token)
    assert_equal 303, client.response.status
    location = client.response.location
    assert_includes location, "site_id=#{@site.id}"
    assert_includes location, "/dashboard/studio/editors/video/"
    scene = StudioProject.find_by!(request_key: "campaign-#{@campaign.id}-actor-#{@alice.id}").studio_scenes.first!
    client.get location, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, 'data-editor-kind="video"'
    client.get "/dashboard/studio-broadcasting/workspace/#{scene.id}?site_id=#{@site.id}&workspace=script", headers: headers.merge("Accept"=>"text/html")
    doc = Nokogiri::HTML(client.response.body)
    assert_equal @site.host, doc.at_css(".business-workspace-identity span").text
    assert_equal "false", doc.at_css("[data-studio-focus]")["aria-pressed"]
    doc.css(".business-workspace a").each { |link| assert_includes link["href"], "site_id=#{@site.id}" }
    if ENV["STUDIO_WORKSPACE_PREVIEW_DIR"]
      folder = ENV.fetch("STUDIO_WORKSPACE_PREVIEW_DIR")
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, "workspace.html"), client.response.body)
      File.write(File.join(folder, "context.json"), {site_id: @site.id, scene_id: scene.id, project: {id: scene.studio_project_id, name: scene.studio_project.name, productions: [], unassigned_scenes: [{id: scene.id, name: scene.name, settings: scene.settings, objects: [], lock_version: scene.lock_version}]}}.to_json)
    end
    client.post url, headers: headers
    assert_equal 422, client.response.status
    client.post "/dashboard/marketing/campaigns/#{@campaign.id}/studio?site_id=#{@other_site.id}", headers: headers.merge("X-CSRF-Token" => token)
    assert_equal 404, client.response.status
  end
end
