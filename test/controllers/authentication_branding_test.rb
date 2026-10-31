# frozen_string_literal: true
require "test_helper"
require "base64"
class AuthenticationBrandingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  PASSWORD = "branding-test-password"
  setup do
    @owner = actor("admin")
    @other = actor("admin")
    @site = DymondSite::Site.create!(name: "Moonlight Studio", host: "moon-#{SecureRandom.hex(6)}.example.test", tenant: @owner,
      manifest: {"unrelated" => "preserved", "authentication_branding" => {"headline" => "Your creative home", "description" => "Made for our people."}})
    @template = DymondSite::SiteTemplate.create!(name: "Shared design", key: "brand-#{SecureRandom.hex(6)}", preset: true,
      settings: {"tokens" => {"color_primary" => "#267a65", "color_bg" => "#10191a", "font_heading" => "Georgia"}, "nav_layout" => "left"})
    @site.update!(active_template: @template)
    @second = DymondSite::Site.create!(name: "Other Company", host: "other-#{SecureRandom.hex(6)}.example.test", tenant: @other, active_template: @template)
  end
  test "public sign in uses the exact host website identity and shared design" do
    host! @site.host
    get new_session_path
    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_select "title", "Sign in · Moonlight Studio"
    assert_select ".auth-wordmark", "Moonlight Studio"
    assert_select ".auth-story-copy h2", text: /Your creative home/
    assert_includes response.body, "--auth-gold:#267a65"
    refute_includes response.body, "lightek-auth-mark.svg"
    refute_includes response.body, "Other Company"
  end
  test "branding cannot be selected by site_id or leak from the first website" do
    host! @second.host
    get new_session_path, params: {site_id: @site.id}
    assert_select ".auth-wordmark", "Other Company"
    refute_includes response.body, "Moonlight Studio"
    host! "unregistered.example.test"
    get new_session_path, params: {site_id: @site.id}
    refute_includes response.body, "Moonlight Studio"
    refute_includes response.body, "Other Company"
  end
  test "password recovery and native setup share the website brand and keep CSRF policy" do
    host! @site.host
    get new_password_path
    assert_response :success
    assert_select ".auth-wordmark", "Moonlight Studio"
    token = @owner.generate_token_for(:password_reset)
    get edit_password_path(token)
    assert_response :success
    assert_select ".auth-wordmark", "Moonlight Studio"
    assert_select "input[name=password_confirmation]"
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end
  test "registration is branded and can only create a client account" do
    host! @site.host
    get sign_up_path
    assert_response :success
    assert_select ".auth-wordmark", "Moonlight Studio"
    email = "brand-client-#{SecureRandom.hex(6)}@example.test"
    post registrations_path, params: {user: {first_name: "New", last_name: "Member", email_address: email, password: PASSWORD, password_confirmation: PASSWORD, role: "super_admin"}}
    assert_response :see_other
    assert_equal "client", User.find_by!(email_address: email).role
  end
  test "invalid registration retains the brand and does not create a user" do
    host! @site.host
    assert_no_difference "User.count" do
      post registrations_path, params: {user: {first_name: "New", last_name: "Member", email_address: "broken", password: PASSWORD, password_confirmation: "different"}}
    end
    assert_response :unprocessable_entity
    assert_select ".auth-wordmark", "Moonlight Studio"
    assert_select "[role=alert]"
  end
  test "owner saves branding through dashboard without changing shared templates or unrelated settings" do
    login(@owner)
    get dashboard_authentication_branding_path(site_id: @site.id)
    assert_response :success
    patch dashboard_authentication_branding_path(site_id: @site.id), params: {branding: {headline: "Welcome to Moonlight", color_primary: "#654321", font_heading: "Lora"}}
    assert_response :see_other
    assert_equal "Welcome to Moonlight", @site.reload.manifest.dig("authentication_branding", "headline")
    assert_equal "preserved", @site.manifest["unrelated"]
    assert_equal "#654321", @site.active_template.settings.dig("tokens", "color_primary")
    assert_equal "#267a65", @second.reload.active_template.settings.dig("tokens", "color_primary")
    assert_equal "#267a65", @template.reload.settings.dig("tokens", "color_primary")
    assert_equal "left", @site.active_template.settings["nav_layout"]
  end
  test "other admins cannot inspect or edit branding and platform super admin can" do
    login(@other)
    get dashboard_authentication_branding_path(site_id: @site.id)
    assert_response :not_found
    patch dashboard_authentication_branding_path(site_id: @site.id), params: {branding: {headline: "stolen"}}
    assert_response :not_found
    login(actor("super_admin"))
    get dashboard_authentication_branding_path(site_id: @site.id)
    assert_response :success
  end
  test "invalid styles and oversized copy cannot be stored" do
    login(@owner)
    original = @site.manifest.deep_dup
    [{color_primary: "red;}</style><script>bad</script>"}, {font_heading: "url(https://evil.test)"}, {headline: "x" * 121}].each do |values|
      patch dashboard_authentication_branding_path(site_id: @site.id), params: {branding: values}
      assert_response :unprocessable_entity
      assert_equal original, @site.reload.manifest
    end
  end
  test "welcome text is escaped and unsafe legacy images cannot be rendered" do
    @site.update!(manifest: {"authentication_branding" => {"headline" => "<script>alert(1)</script>", "background_url" => "javascript:alert(1)"}})
    host! @site.host
    get new_session_path
    assert_response :success
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes response.body, "<script>alert(1)</script>"
    refute_includes response.body, "javascript:alert"
    @template.update_columns(settings: {"tokens" => {"font_heading" => "</style><script>bad</script>", "color_primary" => "expression(bad)"}})
    get new_session_path
    refute_includes response.body, "expression(bad)"
    refute_includes response.body, "<script>bad</script>"
  end
  test "uploaded logos use existing website storage and shared logo setting" do
    login(@owner)
    Tempfile.create(["branding", ".png"]) do |file|
      file.binmode
      file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j1ZkAAAAASUVORK5CYII="));file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      DymondCompute::Storage.stub(:ingest, ->(*) { Struct.new(:id, :url).new(987, "/brand-logo.png") }) do
        patch dashboard_authentication_branding_path(site_id: @site.id), params: {branding: {headline: "Moonlight"}, logo: upload}
      end
      assert_response :see_other
      assert_equal 987, @site.reload.active_template.settings["logo_asset_id"]
      DymondCompute::Storage.stub(:url_for, ->(id) { assert_equal 987, id; "/brand-logo.png" }) do
        host! @site.host
        get new_session_path
        assert_select ".auth-brand img[src='/brand-logo.png']"
      end
    end
  end
  test "dashboard branding requires CSRF even for an authenticated JSON request" do
    login(@owner)
    previous = Dashboard::AuthenticationBrandingController.allow_forgery_protection
    Dashboard::AuthenticationBrandingController.allow_forgery_protection = true
    patch dashboard_authentication_branding_path(site_id: @site.id), params: {branding: {headline: "no token"}}, as: :json
    assert_response :unprocessable_entity
  ensure
    Dashboard::AuthenticationBrandingController.allow_forgery_protection = previous
  end
  private
  def actor(role)
    User.create!(first_name: "Brand", last_name: "Test", role: role, email_address: "brand-#{SecureRandom.hex(8)}@example.test", password: PASSWORD)
  end
  def login(user)
    post session_path, params: {email_address: user.email_address, password: PASSWORD}
    assert_response :redirect
  end
end
