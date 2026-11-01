# frozen_string_literal: true
require_relative "studio_library_checks"
require File.join(ROOT,"app/services/studio/providers/blender_provider")
class NativeBlenderTest < StudioLibraryTest
  StudioLibraryTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def native_fixture(root)
    path=File.join(root,"template.blend")
    script=File.join(root,"make.py")
    File.write(script, <<~PY)
      import bpy
      from mathutils import Vector
      bpy.ops.wm.read_factory_settings(use_empty=True)
      scene=bpy.context.scene;scene.name='Native Stage'
      bpy.ops.mesh.primitive_cube_add();cube=bpy.context.object;cube.name='NativeCube'
      material=bpy.data.materials.new('Native material');material.use_nodes=True;cube.data.materials.append(material)
      image=bpy.data.images.new('Packed texture',width=8,height=8);image.pixels=[0.2,0.6,0.8,1]*64;image.pack()
      texture=material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
      material.node_tree.links.new(texture.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
      nodes=bpy.data.node_groups.new('Native Geometry','GeometryNodeTree');nodes.interface.new_socket(name='Geometry',in_out='INPUT',socket_type='NodeSocketGeometry');nodes.interface.new_socket(name='Geometry',in_out='OUTPUT',socket_type='NodeSocketGeometry')
      incoming=nodes.nodes.new('NodeGroupInput');outgoing=nodes.nodes.new('NodeGroupOutput');nodes.links.new(incoming.outputs['Geometry'],outgoing.inputs['Geometry'])
      modifier=cube.modifiers.new('Native nodes','NODES');modifier.node_group=nodes
      rig=bpy.data.objects.new('CameraRig',None);scene.collection.objects.link(rig);rig.location=(1,0,0)
      armature=bpy.data.objects.new('PreservedRig',bpy.data.armatures.new('PreservedBones'));scene.collection.objects.link(armature)
      camera=bpy.data.objects.new('OriginalCamera',bpy.data.cameras.new('OriginalLens'));scene.collection.objects.link(camera);camera.parent=rig
      camera.location=(6,-7,4);camera.rotation_euler=(Vector((0,0,0))-camera.matrix_world.translation).to_track_quat('-Z','Y').to_euler()
      camera.data.lens=35;camera.data.sensor_width=32;camera.data.shift_x=0.2;camera.data.dof.use_dof=True;camera.data.dof.focus_object=cube;camera.data.dof.aperture_fstop=2
      camera.data.keyframe_insert(data_path='lens',frame=1);camera.data.lens=60;camera.data.keyframe_insert(data_path='lens',frame=10)
      second=bpy.data.objects.new('SecondShot',camera.data);scene.collection.objects.link(second);second.location=(-5,-5,3)
      scene.camera=camera;scene.frame_set(1);scene.render.engine='CYCLES';scene.cycles.samples=1;scene.cycles.use_denoising=False
      scene.world=bpy.data.worlds.new('NativeWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(0.1,0.2,0.3,1)
      scene.use_nodes=True;scene.render.resolution_x=128;scene.render.resolution_y=128;scene.render.resolution_percentage=100
      other=bpy.data.scenes.new('Top View');other.collection.objects.link(cube)
      top=bpy.data.objects.new('TopCamera',bpy.data.cameras.new('TopLens'));other.collection.objects.link(top);top.location=(0,0,8);top.data.type='ORTHO';top.data.ortho_scale=8;other.camera=top
      readme=bpy.data.texts.new('README');readme.write('Fixture attribution — native scene test')
      bpy.ops.wm.save_as_mainfile(filepath=#{path.inspect})
    PY
    output,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",script)
    assert status.success?,"#{output}\n#{error}"
    path
  end
  def imported_native(path)
    asset=StudioAsset.new(owner:@alice,site:@site,name:"Native template",kind:"blend",request_key:SecureRandom.uuid,metadata:{"source"=>{"name"=>"Fixture","author"=>"Test author","license"=>"CC0","source_page"=>"https://www.blender.org/download/demo-files/"}})
    asset.file.attach(io:File.open(path),filename:"template.blend",content_type:"application/x-blender",identify:false);asset.save!
    Rails.stub(:root,Pathname(ROOT)) { Studio::Assets::Ingestor.call(asset) }
    asset.reload
  end
  def test_native_import_retains_the_original_and_preserves_scenes_nodes_rigs_cameras_and_credits
    skip "Native Blender verification requested with LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-import-") do |root|
      asset=imported_native(native_fixture(root))
      assert asset.native.attached?
      assert asset.proxy.attached?
      assert_equal ["Native Stage","Top View"],asset.metadata["scenes"].map { |scene| scene["name"] }
      source=asset.metadata["scenes"].find { |scene| scene["name"]=="Native Stage" }
      assert_equal 1,source["geometry_nodes_count"]
      assert_equal 1,source["armature_count"]
      assert source["compositor"]
      assert_equal "NativeWorld",source["world"]
      assert_equal "OriginalCamera",source["active_camera"]
      assert_in_delta 35,source["cameras"].first.dig("definition","lens"),0.001
      assert_equal "Test author",asset.metadata.dig("source","author")
      assert_equal [],asset.metadata["missing_dependencies"]
      assert_includes asset.metadata["readmes"].first["text"],"Fixture attribution"
    end
  end
  def test_native_template_copy_renders_from_blender_source_and_camera_edits_survive_export
    skip "Native Blender verification requested with LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-render-") do |root|
      asset=imported_native(native_fixture(root))
      payload={asset_id:asset.id,source_scene:"Native Stage",name:"My native production",request_key:SecureRandom.hex(16)}
      receipt=action("blender_template_use",**payload)
      assert_equal receipt,action("blender_template_use",**payload)
      scene=StudioScene.find(receipt[:scene_id]);camera=scene.scene_objects.find_by!(object_type:"camera")
      assert scene.blender_source.attached?
      original=asset.native.blob.download
      result=action("blender_camera_save",scene_id:scene.id,object_id:camera.id,lock_version:scene.lock_version,active:true,
        properties:{lens:85,sensor_width:36,shift_x:0.35,dof_enabled:true,focus_distance:3,focus_object_name:"",aperture_fstop:1.8,aperture_blades:7})
      assert_equal camera.id,result[:object_id]
      manifest=Blender::ManifestBuilder.new(scene.reload).call
      manifest["scene"]["settings"].merge!("resolution_x"=>128,"resolution_y"=>128,"samples"=>1)
      assert_equal "Test author",manifest["credits"].first["author"]
      operation=scene.studio_project.studio_operations.create!(studio_scene:scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      assert_equal scene.blender_source.blob.id,operation.blender_source.blob.id
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"render")
      Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(operation).call }
      assert operation.artifacts.find_by!(kind:"preview").file.attached?
      blend=operation.artifacts.find_by!(kind:"blend")
      blend.file.blob.open do |file|
        check="import bpy,json; s=bpy.context.scene; c=s.camera.data; print('NATIVE='+json.dumps({'scene':s.name,'camera':s.camera.name,'lens':c.lens,'other_lens':bpy.data.objects['SecondShot'].data.lens,'shift':c.shift_x,'dof':c.dof.use_dof,'fstop':c.dof.aperture_fstop,'geometry':len(bpy.data.node_groups),'rigs':len(bpy.data.armatures),'compositor':s.use_nodes,'packed':bool(bpy.data.images.get('Packed texture').packed_file)}))"
        output,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background",file.path,"--python-expr",check)
        assert status.success?,error
        data=JSON.parse(output.lines.find { |line| line.start_with?("NATIVE=") }.split("=",2).last)
        assert_equal "Native Stage",data["scene"]
        assert_equal "OriginalCamera",data["camera"]
        assert_in_delta 85,data["lens"],0.001
        assert_in_delta 35,data["other_lens"],0.001
        assert_in_delta 0.35,data["shift"],0.001
        assert data["dof"]
        assert_in_delta 1.8,data["fstop"],0.001
        assert data["geometry"]>0
        assert data["rigs"]>0
        assert data["compositor"]
        assert data["packed"]
      end
      assert_equal original,asset.native.blob.download,"Template source must remain unchanged"
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_camera_presets_and_validation_are_native_blender_values
    presets=Studio::NativeBlender::CameraSettings.presets
    assert_equal %w[ORTHO PANO PERSP],presets.map { |preset| preset[:settings]["camera_type"] }.uniq.sort
    presets.each do |preset|
      receipt=action("blender_camera_create",scene_id:@scene.id,lock_version:@scene.reload.lock_version,preset:preset[:key],request_key:SecureRandom.hex(16))
      camera=SceneObject.find(receipt["object_id"])
      assert_equal preset[:settings]["camera_type"],camera.definition["camera_type"]
      assert_equal camera.id,@scene.reload.settings["active_camera_object_id"]
    end
    settings=Studio::NativeBlender::CameraSettings
    assert_raises(ArgumentError) { settings.normalize({clip_start:100,clip_end:1}) }
    assert_raises(ArgumentError) { settings.normalize({camera_type:"javascript"}) }
    assert_raises(ArgumentError) { settings.normalize({lens:"NaN"}) }
    assert_raises(ArgumentError) { settings.normalize({aperture_blades:2}) }
  end
  def test_native_template_and_camera_actions_keep_tenant_and_stale_save_boundaries
    @alice.update!(role:"member")
    foreign=StudioAsset.create!(owner:@bob,site:@other_site,name:"Private Blender file",kind:"blend",status:"ready",request_key:SecureRandom.uuid)
    assert_raises(ActiveRecord::RecordNotFound) { action("blender_template_use",asset_id:foreign.id,request_key:SecureRandom.hex(16)) }
    receipt=action("blender_camera_create",scene_id:@scene.id,lock_version:0,preset:"standard_50",request_key:SecureRandom.hex(16))
    camera=SceneObject.find(receipt["object_id"])
    assert_raises(ArgumentError) { action("blender_camera_save",scene_id:@scene.id,lock_version:0,object_id:camera.id,properties:{lens:100},active:false) }
    assert_equal 50,camera.reload.definition["lens"]
  end
  def test_official_demo_catalog_can_be_queued_without_accepting_arbitrary_download_urls
    data=action("assets_list")
    assert_equal 12,data[:blender_demos].length
    assert_equal 7,data[:camera_presets].length
    data[:blender_demos].each { |demo| assert_includes Studio::NativeBlender::DemoImport::HOSTS,URI.parse(demo["url"]).host;assert demo["author"].present?;assert demo["license"].present? }
    first=action("blender_demo_import",demo_key:"pebble_scattering")
    again=action("blender_demo_import",demo_key:"pebble_scattering")
    assert_equal first[:asset_id],again[:asset_id]
    assert_equal "uploaded",first[:status]
    assert_raises(ArgumentError) { action("blender_demo_import",demo_key:"https://example.test/private") }
    assert_raises(ArgumentError) { Studio::NativeBlender::DemoImport.download("http://127.0.0.1/secret","/tmp/unused") }
    asset=StudioAsset.find(first[:asset_id]);asset.update!(status:"failed")
    assert_equal "uploaded",action("blender_demo_import",demo_key:"pebble_scattering")[:status]
  end
  def test_panoramic_orthographic_and_dof_are_written_to_real_blender_cameras
    skip "Native Blender verification requested with LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("camera-native-") do |root|
      objects=Studio::NativeBlender::CameraSettings.presets.map.with_index do |preset,index|
        {"id"=>index+1,"name"=>preset[:key],"type"=>"camera","definition"=>preset[:settings].merge("location"=>[6,-8,4],"rotation"=>[72,0,0])}
      end
      op=@project.studio_operations.create!(operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",manifest:{"schema_version"=>"1.0","scene"=>{"settings"=>{"render_engine"=>"CYCLES","active_camera_object_id"=>5},"objects"=>objects},"outputs"=>{"blend"=>true}})
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      result=Rails.stub(:root,Pathname(ROOT)) { Blender::Runner.new(op).call }
      check="import bpy,json; print('CAMERAS='+json.dumps({o.name:{'type':o.data.type,'lens':o.data.lens,'ortho':o.data.ortho_scale,'dof':o.data.dof.use_dof,'panorama':getattr(getattr(o.data,'cycles',o.data),'panorama_type',None)} for o in bpy.context.scene.objects if o.type=='CAMERA'})); print('ACTIVE='+bpy.context.scene.camera.name)"
      output,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--python-expr",check)
      assert status.success?,error
      cameras=JSON.parse(output.lines.find { |line| line.start_with?("CAMERAS=") }.split("=",2).last)
      assert_equal "PANO",cameras["panorama_360"]["type"]
      assert_equal "FISHEYE_EQUIDISTANT",cameras["fisheye"]["panorama"]
      assert_equal "ORTHO",cameras["orthographic"]["type"]
      assert_equal 8,cameras["orthographic"]["ortho"]
      assert cameras["portrait_85"]["dof"]
      assert_includes output,"ACTIVE=orthographic"
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_official_demo_import_job_downloads_and_prepares_a_native_library_asset
    skip "Set LIGHTEK_TEST_BLENDER_DOWNLOAD=1 for the official network import proof" unless ENV["LIGHTEK_TEST_BLENDER_DOWNLOAD"]=="1"
    result=action("blender_demo_import",demo_key:"pebble_scattering")
    Rails.stub(:root,Pathname(ROOT)) { StudioBlenderDemoImportJob.perform_now(result[:asset_id]) }
    asset=StudioAsset.find(result[:asset_id])
    assert_equal "ready",asset.status
    assert asset.native.attached?
    assert_equal "CC0",asset.metadata.dig("source","license")
    assert asset.file.blob.download.bytesize>0
    assert asset.native.blob.download.bytesize>0
    assert_match(/\A[0-9a-f]{64}\z/,asset.metadata["source_sha256"])
  end
  def test_demo_archives_and_editable_exports_retain_external_media_resources
    skip "Native Blender verification requested with LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-bundle-") do |root|
      source=native_fixture(root)
      FileUtils.mkdir_p(File.join(root,"media"))
      _out,error,status=Open3.capture3("ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=blue:s=128x128:r=24","-t","1","-c:v","libx264","-threads","1",File.join(root,"media/clip.mp4"))
      assert status.success?,error
      code="import bpy; bpy.context.scene.sequence_editor_create().sequences.new_movie('Bundled clip','//media/clip.mp4',channel=1,frame_start=1); bpy.context.scene.render.use_sequencer=False; bpy.ops.wm.save_as_mainfile(filepath=#{source.inspect},check_existing=False)"
      _out,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background",source,"--python-expr",code)
      assert status.success?,error
      zip=File.join(root,"fixture.zip")
      code="import zipfile; z=zipfile.ZipFile(#{zip.inspect},'w'); z.write(#{source.inspect},'template.blend'); z.write(#{File.join(root,'media/clip.mp4').inspect},'media/clip.mp4'); z.close()"
      _out,error,status=Open3.capture3("python3","-c",code)
      assert status.success?,error
      receipt=action("blender_demo_import",demo_key:"classroom")
      downloader=->(_url,destination,**_options) { FileUtils.cp(zip,destination) }
      Rails.stub(:root,Pathname(ROOT)) do
        Studio::NativeBlender::DemoImport.stub(:download,downloader) { StudioBlenderDemoImportJob.perform_now(receipt[:asset_id]) }
      end
      asset=StudioAsset.find(receipt[:asset_id]);assert_equal "ready",asset.status
      assert asset.bundle.attached?
      assert_equal "template.blend",asset.metadata["bundle_relative_source"]
      result=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.hex(16))
      scene=StudioScene.find(result[:scene_id]);assert scene.blender_bundle.attached?
      manifest=Blender::ManifestBuilder.new(scene).call
      manifest["scene"]["settings"].merge!("resolution_x"=>128,"resolution_y"=>128,"samples"=>1)
      assert manifest["outputs"]["bundle"]
      op=scene.studio_project.studio_operations.create!(studio_scene:scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"render")
      Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call }
      package=op.artifacts.find_by!(kind:"package")
      package.file.blob.open do |file|
        unpacked=File.join(root,"unpacked")
        _out,error,status=Open3.capture3("python3",File.join(ROOT,"blender/extract_demo.py"),file.path,unpacked)
        assert status.success?,error
        assert File.file?(File.join(unpacked,"native-bundle/media/clip.mp4"))
        check="import bpy,os; s=bpy.context.scene.sequence_editor.sequences_all[0]; print('MEDIA_EXISTS='+str(os.path.isfile(bpy.path.abspath(s.filepath))))"
        output,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background",File.join(unpacked,"scene.blend"),"--python-expr",check)
        assert status.success?,error
        assert_includes output,"MEDIA_EXISTS=True"
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_official_demo_files_retain_native_node_graphs
    skip "Set LIGHTEK_BLENDER_DEMO_DIR to downloaded official fixtures" unless ENV["LIGHTEK_BLENDER_DEMO_DIR"]
    path=File.join(ENV.fetch("LIGHTEK_BLENDER_DEMO_DIR"),"pebbles.blend")
    asset=imported_native(path)
    assert asset.native.attached?
    assert asset.metadata["scenes"].sum { |scene| scene["geometry_nodes_count"] }>0
    assert asset.metadata["native_blender"]
  end
end
