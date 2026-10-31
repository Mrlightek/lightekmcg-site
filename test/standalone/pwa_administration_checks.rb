# frozen_string_literal: true
require_relative "pwa_http_checks"
require File.join(ROOT, "app/services/lightek_pwa/bootstrap")
require File.join(ROOT, "app/models/concerns/lightek_pwa_site")
DymondSite::Site.include(LightekPwaSite)
ActiveRecord::Schema.define do
  create_table(:profile_sections) { |t| t.integer :profile_id; t.string :key; t.integer :position, default: 0; t.boolean :enabled, default: true; t.json :settings, default: {} }
  create_table(:lightek_agency_site_memberships) do |t|
    t.integer :site_id; t.integer :user_id; t.integer :granted_by_id; t.string :role
  end
end
require File.join(ROOT, "app/models/lightek_agency/site_membership")
require File.join(ROOT, "app/models/profile_section")
class Profile
  has_many :profile_sections
  def cover_image_url = nil
end
class User
  def can_access_feature?(_key) = false
end

# Only the private dashboard host's authentication/layout boundary is replaced.
module Dashboard; end
module DymondDash
  class ApplicationController < ::ApplicationController; end
end
require File.join(ROOT, "app/controllers/dashboard/settings_home_controller")
require File.join(ROOT, "app/controllers/dashboard/pwa_controller")
Dashboard::PwaController.layout false
Dashboard::PwaController.prepend_view_path(File.join(ROOT, "app/views"))
Rails.application.routes.append do
  get "/api/nevaeh/bootstrap", to: "api/nevaeh#bootstrap"
  get "/dashboard/pwa", to: "dashboard/pwa#show", as: :dashboard_pwa
  patch "/dashboard/pwa", to: "dashboard/pwa#update"
  patch "/dashboard/pwa/records/:kind/:id", to: "dashboard/pwa#moderate", as: :dashboard_pwa_record
  post "/dashboard/pwa/communities/:id/members", to: "dashboard/pwa#community_invite", as: :dashboard_pwa_community_members
  post "/dashboard/pwa/people", to: "dashboard/pwa#invite", as: :dashboard_pwa_people
  get "/dashboard/pwa/media/:kind/:id", to: "dashboard/pwa#media", as: :dashboard_pwa_media
  get "/api/lightek/pwa/manifest", to: "api/lightek_pwa#manifest"
  get "/my/installations", to: "dashboard/pwa#show", as: :installations
  get "/dashboard/website/settings", to: "dashboard/pwa#show", as: :dashboard_website_settings
  get "/dashboard/commerce/products", to: "dashboard/pwa#show", as: :dashboard_commerce_products
end
Rails.application.reload_routes!

class PwaAdministrationTest < PwaHttpIntegrationTest
  PwaHttpIntegrationTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @site.update!(tenant: @alice)
    @other_site.update!(tenant: @bob)
    @alice.update!(email_address: "alice@example.test")
    @bob.update!(email_address: "bob@example.test")
    @carol.update!(email_address: "carol@example.test")
    @home = LightekPwa::Surface.create!(key: "home", label: "Home", surface_type: "home")
    @home.modules.create!(key: "following", label: "Following", module_type: "post_grid")
    @home.modules.create!(key: "live-now", label: "Live", module_type: "live_grid", position: 10)
    @watch = LightekPwa::Surface.create!(key: "watch", label: "Watch", surface_type: "watch")
    @studio = LightekPwa::Surface.create!(key: "studio", label: "Studio", surface_type: "studio")
    LightekPwa::NavigationItem.create!(key: "home", label: "Home", surface_key: "home", href: "#/home", placement: "primary")
    LightekPwa::NavigationItem.create!(key: "watch", label: "Watch", surface_key: "watch", href: "#/watch", placement: "primary")
  end
  def admin(actor = @alice, site = @site) = LightekPwa::Administration.new(user: actor, site: site)
  def save_settings(**data) = admin.save!({"lock_version" => admin.application.lock_version}.merge(data.stringify_keys))

  def test_client_owner_and_super_admin_scopes_are_independent_of_account_plan_or_role
    assert_includes LightekPwa::Policy.sites_for(@alice), @site
    refute_includes LightekPwa::Policy.sites_for(@alice), @other_site
    assert_raises(LightekPwa::Policy::Denied) { admin(@alice, @other_site) }
    @carol.update!(role: "super_admin")
    assert_equal 2, LightekPwa::Policy.sites_for(@carol).count
    assert admin(@carol, @other_site).policy.owner?
    LightekPwa::Membership.create!(site: @site, profile: @carol.profile, status: "suspended")
    assert LightekPwa::Policy.new(user: @carol, site: @site).authorize!("studio")
  end

  def test_new_site_automatically_gets_its_own_named_application
    site = DymondSite::Site.create!(name: "Tiffany's community", host: "tiffany.test", tenant: @bob)
    assert_equal "Tiffany's community", site.pwa_application.name
    assert_equal site.id, site.pwa_application.site_id
    assert_equal @bob, site.tenant
  end

  def test_settings_override_the_site_bootstrap_without_editing_global_defaults
    saved = save_settings(name: "Dymondcutz", short_name: "Dymond", theme_color: "#dd7722", surfaces: {"watch" => {"enabled" => "0", "label" => "Our shows", "position" => "1"}, "home" => {"enabled" => "1", "label" => "Welcome", "heading" => "Our people", "modules" => {"following" => {"label" => "Stories", "enabled" => "1", "position" => "2"}, "live-now" => {"enabled" => "0"}}}}, navigation: {"home" => {"enabled" => "1", "label" => "The network", "href" => "#/home", "surface_id" => "home", "placement" => "primary", "position" => "1"}})
    config = LightekPwa::Configuration.new(@site)
    assert_equal "Dymondcutz", config.app.display_name
    assert_equal ["home", "studio"], config.surfaces.map { |surface| surface[:key] }
    assert_equal ["following"], config.surfaces.first[:modules].map { |mod| mod[:key] }
    assert_equal "Stories", config.surfaces.first[:modules].first[:label]
    assert_equal "The network", config.navigation.first[:label]
    assert_equal "Home", @home.reload.label
    assert_equal "Following", @home.modules.find_by!(key: "following").label
    assert_equal "Client", LightekPwa::Configuration.new(@other_site).app.display_name
    assert_equal 2, LightekPwa::Configuration.new(@other_site).navigation.length
    assert_equal saved.id, LightekPwa::Application.find_by!(site: @site).id
    assert_equal 1, LightekPwa::AdminEvent.where(site: @site, actor: @alice).count
    assert_raises(ActiveRecord::StaleObjectError) { admin.save!("lock_version" => 0, "name" => "Stale") }
    assert_raises(ActiveRecord::RecordInvalid) { save_settings(navigation: {"x" => {"enabled" => "1", "href" => 'javascript:alert(1)', "label" => "Bad"}}) }
  end

  def test_moderation_and_membership_updates_never_cross_sites
    mine = publish
    theirs = publish(@bob, site_id: @other_site.id) # helper derives the site; create explicitly below.
    Post.find(theirs[:id]).update!(site_id: @other_site.id)
    admin.moderate!("post", mine[:id], {"moderation_state" => "hidden"})
    assert_empty read(@carol)[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { admin.moderate!("post", theirs[:id], {"content" => "Wrong site"}) }
    assert_equal "Our stories", Post.find(theirs[:id]).content
    assert_raises(LightekPwa::Policy::Denied) { admin.add_administrator!(email: @alice.email_address, role: "member") }
    admin.add_administrator!(email: @carol.email_address, role: "moderator")
    assert_equal "member", @carol.reload.role
    policy = LightekPwa::Policy.new(user: @carol, site: @site)
    assert policy.authorize_admin!("content")
    assert_raises(LightekPwa::Policy::Denied) { policy.authorize_admin!("settings") }
    admin.moderate!("membership", @carol.profile.id, {"status" => "suspended"})
    assert_raises(LightekPwa::Policy::Denied) { policy.authorize!("home") }
  end

  def test_disabled_features_and_suspensions_are_enforced_at_api_and_worker_boundaries
    save_settings(surfaces: {"home" => {"enabled" => "1"}, "studio" => {"enabled" => "0"}})
    client = session_for(@carol)
    Api::NevaehController.allow_forgery_protection = false
    client.post "/api/nevaeh/execute", headers: headers(@carol), params: {capability: "studio.workspace.assets.list", payload: {}}, as: :json
    assert_equal 403, client.response.status
    assert_raises(LightekPwa::Policy::Denied) { Studio::Workers::Workspace.perform("assets_list", user_id: @carol.id, site_id: @site.id) }
    save_settings(status: "maintenance")
    client.get "/api/lightek/pwa?view=feed", headers: headers(@carol)
    assert_equal 403, client.response.status
    assert admin.policy.authorize_admin!("settings")
    @carol.update!(role: "super_admin")
    client.get "/api/lightek/pwa?view=feed", headers: headers(@carol)
    assert_equal 200, client.response.status
  ensure
    Api::NevaehController.allow_forgery_protection = true
  end

  def test_site_admin_can_edit_own_application_studio_projects_but_not_another_site
    one = StudioProject.create!(owner: @carol, site: @site, name: "Member production")
    other = StudioProject.create!(owner: @bob, site: @other_site, name: "Other production")
    access = Studio::PwaAccess.new("user_id" => @alice.id, "site_id" => @site.id)
    assert_includes access.projects, one
    refute_includes access.projects, other
    admin.moderate!("project", one.id, {"name" => "New name"})
    assert_equal "New name", one.reload.name
    op = one.studio_operations.create!(operation_type: "build_scene", provider: "blender", capability: "studio.render.preview", status: "pending")
    admin.moderate!("operation", op.id, {"status" => "cancelled"})
    assert_equal "cancelled", op.reload.status
    op.update!(status: "running")
    admin.moderate!("operation", op.id, {"status" => "cancelled"})
    assert_equal "cancelled", op.reload.status
  end

  def test_manifest_uses_the_requested_site_brand_and_is_not_cached
    save_settings(name: "Nail Salon", short_name: "Salon", background_color: "#161121")
    client = session_for
    client.get "/api/lightek/pwa/manifest"
    assert_equal 200, client.response.status
    assert_equal "Nail Salon", body(client)["name"]
    assert_equal "#161121", body(client)["background_color"]
    assert_equal "private, no-store", client.response.headers["Cache-Control"]
    client.host! "client.test"
    client.get "/api/lightek/pwa/manifest"
    assert_equal "Client", body(client)["name"]
  end

  def test_authenticated_dashboard_renders_actual_forms_and_prevents_other_site_edits
    client = session_for
    publish(title: "The first network story")
    slug = community
    perform("community_join", @carol, slug: slug)
    admin.add_administrator!(email: @carol.email_address, role: "editor")
    project = StudioProject.create!(owner: @carol, site: @site, name: "Community production")
    operation = project.studio_operations.create!(operation_type: "build_scene", provider: "blender", capability: "studio.render.preview", status: "pending")
    artifact = operation.artifacts.create!(kind: "preview", filename: "preview.png")
    artifact.file.attach(io: StringIO.new("image"), filename: "preview.png", content_type: "image/png", identify: false)
    project.studio_publications.create!(artifact: artifact, platform: "lightek_social", status: "scheduled", scheduled_at: 2.hours.from_now)
    StudioAsset.create!(owner: @carol, site: @site, name: "Hero model", kind: "glb", status: "failed", request_key: SecureRandom.uuid, error_message: "Preview could not render")
    project.studio_live_operations.create!(platform: "lightek_streaming", status: "draft", metadata: {"title" => "Community live"})
    perform("community_chat", slug: slug)
    %w[overview settings navigation content communities people studio live conversations audit integrations].each do |section|
      client.get "/dashboard/pwa", params: {site_id: @site.id, section: section}, headers: headers.merge("Accept" => "text/html")
      assert_equal 200, client.response.status, "#{section}: #{client.response.body.first(300)}"
      assert_includes client.response.body, "PWA Administration"
      if ENV["PWA_ADMIN_CAPTURE_DIR"]
        FileUtils.mkdir_p(ENV["PWA_ADMIN_CAPTURE_DIR"])
        File.write(File.join(ENV["PWA_ADMIN_CAPTURE_DIR"], "#{section}.html"), client.response.body)
      end
    end
    %w[assets operations publications].each do |resource|
      client.get "/dashboard/pwa", params: {site_id: @site.id, section: "studio", resource: resource}, headers: headers.merge("Accept" => "text/html")
      assert_equal 200, client.response.status, "studio/#{resource}: #{client.response.body.first(300)}"
    end
    client.get "/dashboard/pwa", params: {site_id: @other_site.id}, headers: headers
    assert_equal 404, client.response.status
    Dashboard::PwaController.allow_forgery_protection = false
    client.patch "/dashboard/pwa", params: {site_id: @site.id, application: {name: "Tiffany PWA", lock_version: 0}}, headers: headers, as: :json
    assert_equal 302, client.response.status
    assert_equal "Tiffany PWA", LightekPwa::Application.find_by!(site: @site).name
    assert_equal @alice, @site.reload.tenant
    client.patch "/dashboard/pwa", params: {site_id: @other_site.id, application: {name: "Stolen", lock_version: 0}}, headers: headers, as: :json
    assert_equal 404, client.response.status
  ensure
    Dashboard::PwaController.allow_forgery_protection = true
  end
  def test_administration_csrf_and_invalid_input_cannot_change_the_application
    client = session_for
    Dashboard::PwaController.allow_forgery_protection = true
    client.patch "/dashboard/pwa", params: {site_id: @site.id, application: {name: "No CSRF", lock_version: 0}}, headers: headers, as: :json
    assert_equal 422, client.response.status
    assert_equal "Lightek", @site.pwa_application.reload.name
    client.get "/test/csrf", headers: headers
    token = body(client).fetch("csrf_token")
    client.patch "/dashboard/pwa", params: {site_id: @site.id, application: {name: "Safe update", lock_version: 0}}, headers: headers.merge("X-CSRF-Token" => token), as: :json
    assert_equal 302, client.response.status
    assert_equal "Safe update", @site.pwa_application.reload.name
  end

  def test_featured_records_are_scoped_and_remain_subject_to_visibility
    featured = publish(title: "Featured story")
    foreign = Post.create!(user: @bob, site: @other_site, title: "Other site", content: "Other site content")
    save_settings(surfaces: {"home" => {"enabled" => "1", "modules" => {"following" => {"enabled" => "1", "label" => "Featured", "post_ids" => featured[:id].to_s}}}})
    assert_equal [featured[:id]], read(@carol)[:featured_posts].map { |post| post[:id] }
    admin.moderate!("post", featured[:id], {"moderation_state" => "hidden"})
    assert_empty read(@carol)[:featured_posts]
    assert_raises(ArgumentError) do
      save_settings(surfaces: {"home" => {"enabled" => "1", "modules" => {"following" => {"enabled" => "1", "post_ids" => foreign.id.to_s}}}})
    end
  end

  def test_maintenance_and_site_suspensions_cannot_be_bypassed_through_legacy_routes_or_receipts
    post = publish
    save_settings(status: "maintenance")
    client = session_for(@carol)
    client.get "/posts.json", headers: headers(@carol)
    assert_equal 403, client.response.status
    client.get "/communities.json", headers: headers(@carol)
    assert_equal 403, client.response.status
    save_settings(status: "published")
    admin.add_administrator!(email: @carol.email_address, role: "member")
    admin.moderate!("membership", @carol.profile.id, {"status" => "suspended"})
    assert_raises(LightekPwa::Policy::Denied) { perform("post_create", @carol, content: "Bypass", request_key: SecureRandom.uuid) }
    client.get "/api/lightek/pwa?view=post&id=#{post[:id]}", headers: headers(@carol)
    assert_equal 403, client.response.status
  end

  def test_conversation_closure_blocks_new_messages_and_does_not_touch_direct_messages
    slug = community
    perform("community_join", @carol, slug: slug)
    chat = perform("community_chat", @carol, slug: slug)
    conversation = LightekMessaging::Conversation.find(chat[:conversation_id])
    admin.moderate!("conversation", conversation.id, {"closed" => "1"})
    assert LightekCommunity::ConversationAccess.allowed?(conversation.reload, @carol.profile)
    assert_raises(LightekMessaging::AccessDenied) do
      LightekMessaging::SendMessage.call(conversation: conversation, sender_profile: @carol.profile, body: "Closed discussion")
    end
    assert_empty conversation.messages
    direct = LightekMessaging::Conversation.create!(kind: "direct", direct_key: "pwa-test-direct", created_by_profile: @alice.profile)
    assert_raises(ActiveRecord::RecordNotFound) { admin.moderate!("conversation", direct.id, {"closed" => "1"}) }
  end

  def test_existing_agency_roles_are_respected_without_changing_global_user_roles
    LightekAgency::SiteMembership.create!(site: @site, user: @carol, granted_by: @alice, role: "manager")
    LightekPwa::Membership.create!(site: @site, profile: @carol.profile)
    policy = LightekPwa::Policy.new(user: @carol, site: @site)
    assert_equal "admin", policy.role
    assert policy.authorize_admin!("settings")
    assert_includes LightekPwa::Policy.sites_for(@carol), @site
    refute_includes LightekPwa::Policy.sites_for(@carol), @other_site
    assert_includes admin.people, @carol.profile
    assert_equal "member", @carol.reload.role
    admin.moderate!("membership", @carol.profile.id, {"status" => "suspended"})
    assert_raises(LightekPwa::Policy::Denied) { policy.authorize_admin!("settings") }
  end

  def test_real_bootstrap_contract_includes_site_settings_and_private_member_state
    save_settings(name: "Tiffany Community", surfaces: {"home" => {"enabled" => "1"}, "watch" => {"enabled" => "0"}})
    client = session_for
    client.get "/api/nevaeh/bootstrap"
    assert_equal 200, client.response.status
    assert_equal "Tiffany Community", body(client).dig("application", "name")
    refute body(client).dig("application", "administration", "can_manage")
    assert_nil body(client)["identity"]
    refute_includes body(client)["surfaces"].map { |surface| surface["key"] }, "watch"
    client.get "/api/nevaeh/bootstrap", headers: headers
    assert_equal 200, client.response.status
    assert body(client).dig("application", "administration", "can_manage")
    assert_includes body(client)["services"].map { |service| service["label"] }, "PWA Administration"
    assert_equal 1, LightekPwa::Membership.where(site: @site, profile: @alice.profile).count
  end

  def test_community_administration_and_unused_asset_removal_preserve_other_applications
    slug = community
    group = Community.find_by!(slug: slug)
    admin.add_community_member!(community_id: group.id, email: @carol.email_address, role: "member")
    member = group.memberships.find_by!(profile: @carol.profile)
    admin.moderate!("community_member", member.id, {"role" => "remove"})
    refute group.reload.member?(@carol.profile)
    assert_raises(LightekPwa::Policy::Denied) { admin.moderate!("community_member", group.memberships.find_by!(profile: @alice.profile).id, {"role" => "remove"}) }
    asset = StudioAsset.create!(site: @site, owner: @carol, name: "Unused prop", kind: "glb", status: "ready", request_key: SecureRandom.uuid)
    project = StudioProject.create!(site: @site, owner: @carol, name: "Production")
    placed = project.studio_scenes.first.scene_objects.create!(name: "Prop", object_type: "imported_asset", definition: {asset_id: asset.id})
    assert_raises(ArgumentError) { admin.moderate!("delete_asset", asset.id, {"status" => "deleted"}) }
    placed.destroy!
    admin.moderate!("delete_asset", asset.id, {"status" => "deleted"})
    refute StudioAsset.exists?(asset.id)
    post = publish
    admin.moderate!("delete_post", post[:id], {"status" => "deleted"})
    refute Post.exists?(post[:id])
  end

  def test_brand_images_can_be_uploaded_and_removed_without_changing_global_icons
    require "base64"
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
    file = Tempfile.new(["pwa-brand", ".png"])
    file.binmode; file.write(png); file.flush
    upload = Rack::Test::UploadedFile.new(file.path, "image/png")
    save_settings(logo: upload, icon: upload)
    application = LightekPwa::Application.find_by!(site: @site)
    assert application.logo.attached?
    assert application.icon.attached?
    manifest = LightekPwa::Configuration.new(@site).manifest
    assert manifest[:icons].first[:src].start_with?("/rails/active_storage/")
    save_settings(remove_logo: "1", remove_icon: "1")
    refute application.reload.logo.attached?
    refute application.icon.attached?
    assert_equal "/lightek/icons/icon-192.png", LightekPwa::Configuration.new(@site).manifest[:icons].first[:src]
  ensure
    file&.close!
  end

  def test_late_payment_callbacks_do_not_restart_an_administratively_cancelled_operation
    project = StudioProject.create!(site: @site, owner: @carol, name: "Cancelled production")
    operation = project.studio_operations.create!(operation_type: "build_scene", provider: "blender", capability: "studio.render.preview", status: "awaiting_payment")
    admin.moderate!("operation", operation.id, {"status" => "cancelled"})
    transaction = Struct.new(:id).new(1234)
    operation.payment_succeeded!(transaction)
    assert_equal "cancelled", operation.reload.status
    assert operation.metadata.dig("payment", "requires_review")
    assert_equal "succeeded", operation.metadata.dig("payment", "status")
    operation.payment_succeeded!(transaction)
    assert_equal "cancelled", operation.reload.status
    operation.payment_failed!(transaction, message: "Delayed failure")
    assert_equal "cancelled", operation.reload.status
  end

end
