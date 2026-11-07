# frozen_string_literal: true
require_relative "studio_authoring_checks"
require File.join(ROOT,"db/migrate/20261107210000_create_studio_workstations")
CreateStudioWorkstations.new.migrate(:up)
%w[app/models/studio_workstation app/services/studio/workstations/runtime app/services/studio/workstations/access app/jobs/studio_workstation_start_job app/jobs/studio_workstation_save_job app/controllers/dashboard/studio_workstations_controller].each { |path| require File.join(ROOT,path) }
Dashboard::StudioWorkstationsController.prepend_view_path(File.join(ROOT,"app/views"));Dashboard::StudioWorkstationsController.layout false
Rails.application.routes.append do
  resources :studio_workstations,path:"/dashboard/studio/workstations",controller:"dashboard/studio_workstations",as: :dashboard_studio_workstations,only:%i[create show destroy] do
    member { get :status;post :ticket;post :save;post :workspace }
  end
end
Rails.application.reload_routes!
class StudioWorkstationTest < StudioAuthoringTest
  StudioAuthoringTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @root=Dir.mktmpdir("workstation-tests-");@previous=ENV["STUDIO_WORKSTATION_ROOT"];ENV["STUDIO_WORKSTATION_ROOT"]=@root
    File.binwrite(File.join(@root,"gateway.key"),"test-key"*8)
  end
  def teardown
    ENV["STUDIO_WORKSTATION_ROOT"]=@previous
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
    super
  end
  def access(user=@alice,site=@site) = Studio::Workstations::Access.new(user:user,site:site)
  def create_session(**payload) = access.create!({"scene_id"=>@scene.id,"request_key"=>SecureRandom.uuid}.merge(payload.stringify_keys),origin:"https://lightek.test")
  def test_workstation_creation_is_idempotent_and_preserves_an_immutable_source_snapshot
    key=SecureRandom.uuid;s=create_session(request_key:key);again=create_session(request_key:key)
    assert_equal s.id,again.id
    assert_equal 1,StudioWorkstation.count
    operation=StudioOperation.find(s.metadata["operation_id"])
    assert_equal({"blend"=>true,"bundle"=>false},operation.manifest["outputs"])
    assert_equal "pending",operation.status
    assert_raises(ArgumentError) { create_session }
    assert_equal 1,StudioWorkstation.count
  end
  def test_workstation_access_rejects_foreign_owners_sites_and_expired_tickets
    s=create_session;s.update!(status:"ready",port:22000)
    @alice.update!(role:"member")
    assert_raises(ActiveRecord::RecordNotFound) { access(@bob).find!(s.session_key) }
    assert_raises(ActiveRecord::RecordNotFound) { access(@alice,@other_site).find!(s.session_key) }
    token=Studio::Workstations::Runtime.ticket(s)
    data,signature=token.split('.')
    expected=Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256","test-key"*8,data),padding:false)
    assert_equal expected,signature
    assert_equal @alice.id,JSON.parse(Base64.urlsafe_decode64(data))["uid"]
    s.update!(expires_at:1.second.ago)
    assert_raises(ArgumentError) { Studio::Workstations::Runtime.ticket(s) }
  end
  def test_workstation_saved_resource_reads_do_not_follow_guest_symlinks
    s=create_session;work=Studio::Workstations::Runtime.work(s);FileUtils.mkdir_p(work)
    outside=File.join(@root,"outside-secret");File.write(outside,"private"*10)
    File.symlink(outside,work.join("scene.blend"))
    assert_raises(Errno::ELOOP) { Studio::Workstations::Runtime.open_saved_file(s,"scene.blend") { |f| f.read } }
    assert_raises(ArgumentError) { Studio::Workstations::Runtime.open_saved_file(s,"../gateway.key") { |f| f.read } }
    assert_equal "private"*10,File.read(outside)
  end
  def test_workstation_start_uses_an_internal_network_loopback_port_and_no_application_mount
    s=create_session;op=StudioOperation.find(s.metadata["operation_id"]);commands=[]
    Dir.mktmpdir("workstation-source-") do |out|
      File.write(File.join(out,"scene.blend"),"BLENDER-v400"+"x"*30)
      provider=Object.new;provider.define_singleton_method(:call){Struct.new(:output_directory).new(Pathname(out))}
      command=->(*args,**_opts){commands<<args;args[0]=="run" ? "a"*64 : args[0]=="port" ? "127.0.0.1:22000" : ""}
      runtime=Studio::Workstations::Runtime
      runtime.stub(:readiness!,nil) do
        runtime.stub(:wait_for_desktop!,nil) do
          runtime.stub(:command,command) do
            Studio::Providers::BlenderProvider.stub(:new,->(_op){provider}) { StudioWorkstationStartJob.perform_now(s.id) }
          end
        end
      end
      run=commands.find{|args|args.first=="run"}
      assert_equal "none",run[run.index("--network")+1]
      refute_includes run,"--publish"
      assert_includes run,"--read-only";assert_includes run,"no-new-privileges"
      mounts=run.each_index.filter_map{|i|run[i+1] if run[i]=="--mount"}
      assert_equal 2,mounts.length
      refute mounts.any?{|value|value.include?("docker.sock") || value.include?("Vault") || value.include?("config/master.key")}
      assert_equal "ready",s.reload.status
      assert_equal "completed",op.reload.status
      state=JSON.parse(File.read(runtime.directory(s).join("session.json")))
      assert_equal @alice.id,state["owner_id"]
    end
  end
  def test_workstation_controller_requires_authentication_and_csrf_then_hides_internal_paths
    Dashboard::StudioWorkstationsController.allow_forgery_protection=true
    client=session_for;client.get "/test/csrf",headers:headers
    token=body(client).fetch("csrf_token")
    client.post "/dashboard/studio/workstations",headers:headers.merge("X-CSRF-Token"=>token),params:{scene_id:@scene.id,request_key:SecureRandom.uuid}
    assert_equal 202,client.response.status,client.response.body
    key=body(client)["session_key"]
    client.get "/dashboard/studio/workstations/#{key}/status",headers:headers
    assert_equal 200,client.response.status
    refute_includes client.response.body,"container_id";refute_includes client.response.body,"gateway.key"
    client.get "/dashboard/studio/workstations/#{key}",headers:headers.merge("Accept"=>"text/html")
    assert_equal 200,client.response.status,client.response.body
    assert_includes client.response.body,"Native Blender production workstation"
    assert_includes client.response.body,"Save version to Studio"
  end
  def test_workstation_real_native_save_returns_to_library_without_changing_the_original
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    s=create_session;s.update!(status:"saving",container_id:"a"*64,port:22000,metadata:s.metadata.merge("save_nonce"=>"b"*16))
    work=Studio::Workstations::Runtime.work(s);FileUtils.mkdir_p(work)
    source=native_fixture(work.to_s);FileUtils.cp(source,work.join("scene.blend"));original=File.binread(source)
    code="import bpy,sys; bpy.ops.wm.open_mainfile(filepath=#{work.join('scene.blend').to_s.inspect},load_ui=False,use_scripts=False); sys.path.insert(0,#{File.join(ROOT,'blender').inspect}); import workstation; bpy.data.objects['NativeCube'].location.x=4; workstation.save_session()"
    command=->(*_args,**_opts){Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python-expr",code],timeout:60)}
    previous=ENV["LIGHTEK_WORKSTATION_TEST_ROOT"];ENV["LIGHTEK_WORKSTATION_TEST_ROOT"]=work.to_s
    Rails.stub(:root,Pathname(ROOT)) do
      Studio::Workstations::Runtime.stub(:command,command) { StudioWorkstationSaveJob.perform_now(s.id) }
    end
    assert_equal "ready",s.reload.status
    asset=StudioAsset.find(s.metadata.fetch("saved_asset_id"));assert_equal "ready",asset.status
    assert asset.native.attached?;assert asset.bundle.attached?
    saved=StudioScene.find(s.metadata.fetch("saved_scene_id"))
    assert_in_delta 4,saved.scene_objects.find_by!(name:"NativeCube").definition["location"][0],0.001
    assert_equal original,File.binread(source)
    saved.update!(settings:saved.settings.merge("render_engine"=>"CYCLES","samples"=>1,"resolution_x"=>64,"resolution_y"=>64,"frame_start"=>1,"frame_end"=>3))
    manifest=Blender::ManifestBuilder.new(saved).call;manifest["outputs"]={"animation"=>true}
    operation=saved.studio_operations.create!(studio_project:saved.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
    previous_output=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(@root,"movie")
    Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(operation).call }
    operation.update!(status:"completed")
    video=operation.artifacts.find_by!(kind:"video");assert video.file.attached?
    publication=action("artifact_publish",project_id:saved.studio_project_id,artifact_id:video.id,platform:"lightek_social",title:"Native workstation proof",request_key:SecureRandom.uuid)
    StudioPublicationDispatchJob.perform_now(publication[:publication_id])
    release=StudioPublication.find(publication[:publication_id]);assert_equal "published",release.status
    assert_equal "video",Post.find(release.metadata.fetch("post_id")).kind
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous_output
    ENV["LIGHTEK_WORKSTATION_TEST_ROOT"]=previous
  end
end
