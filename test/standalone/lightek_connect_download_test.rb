require_relative "lightek_connect_vault_test"
require Rails.root.join("app/services/lightek_connect/wordpress_package")
require Rails.root.join("app/controllers/dashboard/connect_controller")

class LightekConnectDownloadTest < ActionController::TestCase
  tests Dashboard::ConnectController

  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "/dashboard/connect/wordpress.zip", to: "dashboard/connect#wordpress_download" }
  end

  def test_agency_download_contains_installable_plugin_and_current_shared_assets
    @controller.current_user = User.create!(role: "white_label")
    get :wordpress_download
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_includes response.headers["Content-Disposition"], "lightek-connect-wordpress.zip"
    assert_includes response.headers["Cache-Control"], "no-store"
    files = {}
    Zip::InputStream.open(StringIO.new(response.body)) do |archive|
      while (entry = archive.get_next_entry)
        files[entry.name] = archive.read
      end
    end
    assert_equal LightekConnect::WordpressPackage::FILES.keys.map { |path| "lightek-connect/#{path}" }.sort, files.keys.sort
    assert_includes files.fetch("lightek-connect/lightek-connect.php"), "Plugin Name: Lightek Connect"
    assert_equal Rails.root.join("public/lightek-connect/workspace.js").binread, files.fetch("lightek-connect/assets/workspace.js")
    assert_equal Rails.root.join("public/lightek-connect/workspace.css").binread, files.fetch("lightek-connect/assets/workspace.css")
  end

  def test_super_admin_can_download
    @controller.current_user = User.create!(role: "super_admin")
    get :wordpress_download
    assert_response :success
  end

  def test_client_and_anonymous_users_cannot_download
    [User.create!(role: "client"), nil].each do |actor|
      @controller.current_user = actor
      get :wordpress_download
      assert_response :forbidden
      refute_equal "application/zip", response.media_type
    end
  end
end
