require_relative "broadcast_control_checks"
class StudioProjectDeletionChecks < BroadcastControlTest
  def self.runnable_methods = public_instance_methods.grep(/^test_project_deletion/).map(&:to_s)
  def setup
    super
    @project = StudioProject.create!(owner: @alice, site: @site, name: "Delete this production")
    @scene = @project.studio_scenes.first!
    @client = session_for
  end
  def deletion_path(project = @project, site = @site) = "/dashboard/studio-broadcasting/projects/#{project.id}?site_id=#{site.id}"
  def operation(status = "completed")
    @project.studio_operations.create!(studio_scene: @scene, operation_type: "edit_media", provider: "ffmpeg", capability: "studio.editor.export", status: status)
  end
  def test_project_deletion_requires_explicit_confirmation_and_renders_escaped_name
    @project.update!(name: "<script>test</script>")
    @client.get "/dashboard/studio-broadcasting/projects/#{@project.id}/delete?site_id=#{@site.id}", headers: headers
    assert_equal 200, @client.response.status
    assert_includes @client.response.body, "&lt;script&gt;test&lt;/script&gt;"
    assert_includes @client.response.body, 'name="confirmation"'
    @client.delete deletion_path, headers: headers
    assert_equal 303, @client.response.status
    assert StudioProject.exists?(@project.id)
  end
  def test_project_deletion_removes_owned_content_and_preserves_reusable_media_and_billing
    @scene.scene_objects.create!(name: "Shape", object_type: "cube", definition: {})
    @scene.editor_source.attach(io: StringIO.new("source"), filename: "source.json", identify: false)
    op = operation
    artifact = op.artifacts.create!(kind: "video", filename: "export.mp4")
    artifact.file.attach(io: StringIO.new("movie"), filename: "export.mp4", identify: false)
    asset = StudioAsset.create!(owner: @alice, site: @site, studio_project: @project, name: "Reusable video", kind: "video", status: "ready", request_key: SecureRandom.uuid)
    asset.file.attach(artifact.file.blob)
    billing = DymondBank::Transaction.create!(payable_type: "StudioOperation", payable_id: op.id, status: "succeeded")
    other = StudioProject.create!(owner: @bob, site: @other_site, name: "Other production")
    @client.delete deletion_path, params: {confirmation: "delete"}, headers: headers
    assert_equal 303, @client.response.status
    refute StudioProject.exists?(@project.id)
    refute StudioScene.exists?(@scene.id)
    refute StudioOperation.exists?(op.id)
    refute Artifact.exists?(artifact.id)
    refute SceneObject.exists?(studio_scene_id: @scene.id)
    assert StudioProject.exists?(other.id)
    assert_nil asset.reload.studio_project_id
    assert asset.file.attached?
    assert DymondBank::Transaction.exists?(billing.id)
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "StudioScene", record_id: @scene.id).count
  end
  def test_project_deletion_is_site_scoped_even_for_superadmin_and_denies_other_users
    foreign = StudioProject.create!(owner: @bob, site: @other_site, name: "Foreign")
    @client.delete deletion_path(foreign), params: {confirmation: "delete"}, headers: headers
    assert_equal 404, @client.response.status
    @client.delete deletion_path, params: {confirmation: "delete"}, headers: headers(@bob)
    assert_includes [403,404], @client.response.status
    assert StudioProject.exists?(@project.id)
    assert StudioProject.exists?(foreign.id)
  end
  def test_project_deletion_blocks_active_renders_media_and_broadcasts_before_any_cascade
    op = operation("running")
    assert_raises(ActiveRecord::RecordNotDestroyed) { @project.destroy! }
    assert StudioScene.exists?(@scene.id)
    op.update!(status: "completed")
    job = @scene.creation_jobs.create!(status: "pending")
    assert_raises(ActiveRecord::RecordNotDestroyed) { @project.reload.destroy! }
    job.update!(status: "completed")
    asset = StudioAsset.create!(owner: @alice, site: @site, studio_project: @project, name: "Processing", kind: "video", status: "processing", request_key: SecureRandom.uuid)
    assert_raises(ActiveRecord::RecordNotDestroyed) { @project.reload.destroy! }
    asset.update!(status: "ready")
    live = @project.studio_live_operations.create!(platform: "octavia", status: "live")
    assert_raises(ActiveRecord::RecordNotDestroyed) { @project.reload.destroy! }
    live.update!(status: "ended")
    artifact = op.artifacts.create!(kind: "video", filename: "render.mp4")
    publication = @project.studio_publications.create!(platform: "octavia", status: "scheduled", artifact: artifact)
    assert_raises(ActiveRecord::RecordNotDestroyed) { @project.reload.destroy! }
    publication.update!(status: "cancelled")
    @project.reload.destroy!
    refute StudioProject.exists?(@project.id)
  end
  def test_project_deletion_requires_csrf_and_card_links_to_confirmation
    @client.get "/dashboard/studio-broadcasting?site_id=#{@site.id}", headers: headers
    assert_equal 200, @client.response.status
    assert_includes @client.response.body, "/dashboard/studio-broadcasting/projects/#{@project.id}/delete?site_id=#{@site.id}"
    Dashboard::MediaStudioController.allow_forgery_protection = true
    @client.delete deletion_path, params: {confirmation: "delete"}, headers: headers
    assert_includes [403,422], @client.response.status
    assert StudioProject.exists?(@project.id)
  end
  def test_project_deletion_existing_worker_uses_the_same_busy_guard
    operation("pending")
    assert_raises(ActiveRecord::RecordNotDestroyed) do
      Studio::Workers::Workspace.perform("project_delete", {"user_id" => @alice.id, "site_id" => @site.id, "project_id" => @project.id})
    end
    assert StudioProject.exists?(@project.id)
  end
end
