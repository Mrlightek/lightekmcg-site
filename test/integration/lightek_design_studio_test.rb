require "test_helper"
class LightekDesignStudioTest < ActionDispatch::IntegrationTest
  def actor(role = "admin")
    User.create!(first_name: "Designer", last_name: "Test", role: role, email_address: "designer-#{SecureRandom.hex(6)}@example.test", password: "Designer-testing-2026!")
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Designer-testing-2026!"}
    assert_response :redirect
  end
  def workspace(user)
    LightekDesign::StudioDocument.create!(user: user, name: "Client project")
  end
  test "workspace cards offer confirmed deletion and the owner can delete" do
    user = actor; record = workspace(user); login(user)
    get "/dashboard/design-studio"
    assert_response :success
    assert_select "form[action='#{delete_dashboard_design_studio_path(record)}'][data-turbo-confirm]" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "input[type='submit'][value='Delete workspace'], button", count: 1
    end
    delete "/dashboard/design-studio/#{record.id}", params: {revision: 1}
    assert_response :see_other
    refute DymondSite::SiteTemplate.exists?(record.id)
    follow_redirect!
    assert_response :success
  end
  test "delete requires sign in ownership and a current revision" do
    user = actor; record = workspace(user)
    delete "/dashboard/design-studio/#{record.id}", params: {revision: 1}
    assert_response :redirect
    login(actor)
    delete "/dashboard/design-studio/#{record.id}", params: {revision: 1}, as: :json
    assert_response :not_found
    assert DymondSite::SiteTemplate.exists?(record.id)
    login(user)
    delete "/dashboard/design-studio/#{record.id}", params: {revision: 0}, as: :json
    assert_response :conflict
    assert DymondSite::SiteTemplate.exists?(record.id)
    delete "/dashboard/design-studio/#{record.id}", params: {revision: 1}, as: :json
    assert_response :success
    assert_equal dashboard_design_studio_index_path, response.parsed_body["redirect_url"]
  end
  test "anonymous designers must sign in and clients cannot author designs" do
    get "/dashboard/design-studio"
    assert_response :redirect
    login(actor("client"))
    get "/dashboard/design-studio"
    assert_response :forbidden
  end
  test "a designer can create a workspace and open the editor" do
    user = actor; login(user)
    post "/dashboard/design-studio", params: {name: "Our new design"}
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_select "[data-design-studio]"
    assert_select "iframe[sandbox='allow-scripts']"
    assert_select "[data-save-design]", text: "Save draft"
    assert_select "[data-delete-design]", text: "Delete workspace"
    assert_select "[data-publish-design]", text: "Add to design library"
    assert_select "[data-lightek-font-picker]", count: 3
  end
  test "another designer cannot read or alter a workspace" do
    record = workspace(actor)
    original = record.settings.deep_dup
    login(actor)
    get "/dashboard/design-studio/#{record.id}/edit"
    assert_response :not_found
    patch "/dashboard/design-studio/#{record.id}", params: {document: LightekDesign::StudioDocument.draft(record), revision: 1}, as: :json
    assert_response :not_found
    assert_equal original, record.reload.settings
  end
  test "preview renders without writing or publishing client pages" do
    user = actor; record = workspace(user); login(user)
    original = record.settings.deep_dup
    draft = LightekDesign::StudioDocument.draft(record)
    draft["sections"][0]["data"]["heading"] = "<script>window.bad=true</script>"
    post "/dashboard/design-studio/#{record.id}/preview", params: {document: draft}, as: :json
    assert_response :success
    assert_includes response.body, "&lt;script&gt;window.bad=true&lt;/script&gt;"
    assert_select "[data-studio-section]", count: 4
    assert_equal original, record.reload.settings
  end
  test "save conflicts preserve the last saved draft and library release is separate from page publishing" do
    user = actor; record = workspace(user); login(user)
    draft = LightekDesign::StudioDocument.draft(record)
    patch "/dashboard/design-studio/#{record.id}", params: {document: draft.merge("name" => "Saved design"), revision: 1}, as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["revision"]
    patch "/dashboard/design-studio/#{record.id}", params: {document: draft.merge("name" => "Stale changes"), revision: 1}, as: :json
    assert_response :conflict
    assert_equal "Saved design", LightekDesign::StudioDocument.draft(record.reload)["name"]
    assert_no_difference "DymondSite::Page.count" do
      post "/dashboard/design-studio/#{record.id}/publish", params: {document: LightekDesign::StudioDocument.draft(record), revision: 2}, as: :json
    end
    assert_response :success
    assert_equal 1, response.parsed_body.dig("release", "version")
  end
  test "super admin can edit a selected designer workspace" do
    record = workspace(actor); login(actor("super_admin"))
    get "/dashboard/design-studio/#{record.id}/edit"
    assert_response :success
  end
end
