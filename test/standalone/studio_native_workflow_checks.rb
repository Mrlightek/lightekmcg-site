# frozen_string_literal: true
require_relative "studio_ai_checks"
require_relative "studio_cpu_pool_checks"
%w[app/services/studio/layered/motion app/services/studio/layered/composition app/services/studio/layered/templates app/services/studio/layered/runtime app/services/studio/workflows/scene_plan app/services/studio/workflows/production app/services/studio/providers/layered_provider].each { |file| require File.join(ROOT,file) }
module Api; module Lightek; module Pwa; end; end; end
require File.join(ROOT,"app/controllers/api/lightek/pwa/studio_workflows_controller")
require "rack/mock"
Rails.application.routes.draw do
  post "/api/lightek/pwa/studio/workflows/:id/mcp",to:"api/lightek/pwa/studio_workflows#mcp"
end
class StudioNativeWorkflowTest < StudioAiTest
  StudioAiTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def graph
    Studio::Workflows::ScenePlan.parse("A nighttime park with a character sitting on a bench",seed:42)
  end
  def workflow(**extra)
    action("workflow_create",scene_id:@scene.id,composition:graph,request_key:"native-workflow-123",**extra)
  end
  def at_root(&block) = Rails.stub(:root,Pathname(ROOT),&block)
  def rpc(operation,method,params={},token:Studio::Workflows::Production.token(operation),path_id:operation.id,origin:nil)
    env=Rack::MockRequest.env_for("/api/lightek/pwa/studio/workflows/#{path_id}/mcp",method:"POST",
      "CONTENT_TYPE"=>"application/json","HTTP_AUTHORIZATION"=>"Bearer #{token}","HTTP_ORIGIN"=>origin,
      input:JSON.generate({jsonrpc:"2.0",id:1,method:method,params:params}))
    status,_,body=Rails.application.call(env)
    text=body.each.to_a.join;body.close if body.respond_to?(:close)
    [status,text.empty? ? nil : JSON.parse(text)]
  end
  def test_seeded_assets_have_defaults_and_parallax_is_independent_from_stacking
    first=graph
    assert_equal first,graph
    layers=Studio::Layered::Composition.flatten(first)
    assert_operator layers.count { |layer| layer["template"]=="tree.oak" },:>=,3
    assert layers.any? { |layer| layer["template"]=="character.seated" }
    near=layers.find { |layer| layer["depth"]==0.9 };far=layers.find { |layer| layer["depth"]==0.16 }
    move=->(layer) { Studio::Layered::Composition.displacement(first,layer,4).first.abs }
    assert_operator move.call(near),:>,move.call(far)
    changed=first.deep_dup;changed["nodes"].first["z_index"]=100
    assert_equal "sky.day".sub("day","night"),Studio::Layered::Composition.flatten(changed).last["template"]
    assert_equal 0,Studio::Layered::Composition.flatten(changed).last["depth"]
    assert_raises(ArgumentError) { Studio::Workflows::ScenePlan.parse("A dragon flies") }
    unsafe=first.deep_dup;unsafe["camera"]["x"]="1; system('evil')"
    assert_raises(ArgumentError) { Studio::Layered::Composition.normalize(unsafe) }
  end
  def test_asset_and_group_tracks_obey_parent_transforms_and_preview_time
    motion=Studio::Layered::Motion
    composition=graph
    composition["camera"]={"x"=>0,"y"=>0}
    composition["nodes"]=[{"id"=>"rig","rotation"=>90,"scale"=>2,"motion"=>motion.preset("drift_right",amount:0.1,duration:4),
      "children"=>[{"id"=>"part","template"=>"bench","width"=>0.1,"height"=>0.1,"motion"=>motion.preset("float",amount:0.1,duration:4)}]}]
    normalized=Studio::Layered::Composition.normalize(composition)
    layer=Studio::Layered::Composition.flatten(normalized).first
    assert_equal 2,layer["motions"].length
    offsets=layer["motions"].map { |track| motion.offset(track,2) }
    assert_in_delta 32,offsets[0][0],0.0001
    assert_in_delta 72,offsets[1][0],0.0001
    assert_in_delta 0,offsets[1][1],0.0001
    assert_equal [0.0,0.0],motion.offset(layer["motions"][1],4)
    assert_equal [64.0,0.0],motion.offset(layer["motions"][0],8)
    preview=Studio::Workflows::Production.preview(normalized)
    assert_equal normalized["nodes"].first["motion"],preview["nodes"].first["motion"]
    assert_equal 2,preview["canvas"]["duration"]
    looped=motion.preset("sway")
    assert_raises(ArgumentError) { motion.normalize(looped.merge("duration"=>0)) }
    assert_raises(ArgumentError) { motion.normalize(looped.merge("loop"=>"true")) }
    bad=looped.deep_dup;bad["keyframes"][1]["t"]=0
    assert_raises(ArgumentError) { motion.normalize(bad) }
    bad=looped.deep_dup;bad["keyframes"].last["x"]=0.1
    assert_raises(ArgumentError) { motion.normalize(bad) }
    bad=looped.deep_dup;bad["keyframes"][1]["x"]="evil"
    assert_raises(ArgumentError) { motion.normalize(bad) }
    park=Studio::Workflows::ScenePlan.parse("A nighttime park with a character sitting on a bench and a gentle breeze",seed:42)
    assert Studio::Layered::Composition.flatten(park).select { |item| item["template"]=="tree.oak" }.all? { |item| item["motions"].any? }
  end
  def test_nested_compositions_save_and_reopen_without_overwriting_other_settings
    at_root do
      before=@scene.settings.deep_dup
      result=action("workflow_save",scene_id:@scene.id,lock_version:@scene.lock_version,composition:graph)
      assert_equal graph,@scene.reload.settings["composition_2d"]
      assert_equal before,@scene.settings.except("composition_2d")
      assert_equal graph,action("workflow_status",scene_id:@scene.id)[:composition]
      assert_raises(ArgumentError) { action("workflow_save",scene_id:@scene.id,lock_version:result[:lock_version]-1,composition:graph) }
      assert_raises(ActiveRecord::RecordNotFound) { workflow(user_id:@bob.id) }
    end
  end
  def test_snapshot_is_idempotent_and_custom_images_are_tenant_scoped
    at_root do
      result=workflow
      assert_equal result,workflow
      operation=StudioOperation.find(result[:operation_id])
      assert operation.layer_sources.attached?
      assert_equal "layered_2d",operation.provider
      assert_equal [640,360,2,12],operation.manifest["composition_2d"]["canvas"].values_at("width","height","duration","fps")
      other=StudioAsset.create!(owner:@bob,site:@other_site,name:"Other image",kind:"image",status:"ready",request_key:SecureRandom.uuid)
      changed=graph;changed["nodes"][0]["children"]=[{"id"=>"private","asset_id"=>other.id}]
      assert_raises(ActiveRecord::RecordNotFound) { workflow(composition:changed,request_key:"foreign-image-123") }
      invalid=graph;invalid["nodes"]<<{"id"=>"sky","template"=>"bench"}
      assert_raises(ArgumentError) { Studio::Layered::Composition.normalize(invalid) }
    end
  end
  def test_owned_image_is_frozen_before_its_library_source_changes
    at_root do
      red=IO.popen(["convert","-size","16x16","xc:red","PNG:-"],"rb",&:read)
      image=StudioAsset.new(owner:@alice,site:@site,studio_project:@project,name:"Owned image",kind:"image",status:"ready",request_key:SecureRandom.uuid)
      image.file.attach(io:StringIO.new(red),filename:"red.png",content_type:"image/png",identify:false)
      image.save!
      original=image.file.blob
      composition=graph;composition["nodes"]=[{"id"=>"owned-image","asset_id"=>image.id,"width"=>1,"height"=>1}]
      operation=StudioOperation.find(workflow(composition:composition)[:operation_id])
      assert_equal original.id,operation.metadata.dig("layer_blobs","asset:#{image.id}")
      blue=IO.popen(["convert","-size","16x16","xc:blue","PNG:-"],"rb",&:read)
      image.file.attach(io:StringIO.new(blue),filename:"blue.png",content_type:"image/png",identify:false)
      ExecuteStudioOperationJob.perform_now(operation.id)
      assert_equal "completed",operation.reload.status,operation.error_message
      operation.artifacts.find_by!(kind:"video").file.blob.open do |file|
        pixels=IO.popen(["ffmpeg","-v","error","-i",file.path,"-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","-"],"rb",&:read)
        r,g,b=pixels.byteslice((180*640+320)*3,3).bytes
        assert_operator r,:>,200
        assert_operator b,:<,50
      end
    end
  end
  def test_mcp_tokens_remain_job_scoped_without_a_comfyui_server
    at_root do
      operation=StudioOperation.find(workflow[:operation_id])
      assert_equal 200,rpc(operation,"initialize")[0]
      assert_equal %w[studio_render studio_result],rpc(operation,"tools/list")[1].dig("result","tools").map { |tool| tool["name"] }
      assert_equal 403,rpc(operation,"tools/list",{},token:"bad")[0]
      assert_equal 403,rpc(operation,"tools/list",{},path_id:operation.id+1)[0]
      assert_equal 403,rpc(operation,"tools/list",{},origin:"https://other.test")[0]
      assert rpc(operation,"tools/call",{name:"studio_render",arguments:{command:"evil"}})[1].dig("result","isError")
    end
  end
  def test_real_native_2d_render_has_parallax_and_uses_no_comfyui_or_blender
    Studio::Ai::Runtime.stub(:new, ->(*) { flunk "ComfyUI must not be called" }) do
      Blender::Runner.stub(:new, ->(*) { flunk "Blender must not be called" }) do
        at_root do
          assert action("workflow_status",scene_id:@scene.id)[:ready]
          moving=Studio::Workflows::ScenePlan.parse("A nighttime park with a character sitting on a bench and a gentle breeze",seed:42)
          moving["camera"]={"x"=>0,"y"=>0}
          operation=StudioOperation.find(workflow(composition:moving)[:operation_id])
          ExecuteStudioOperationJob.perform_now(operation.id)
          assert_equal "completed",operation.reload.status,operation.error_message
          artifact=operation.artifacts.find_by!(kind:"video")
          artifact.file.blob.open do |file|
            info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
            assert_in_delta 2,info.dig("format","duration").to_f,0.05
            assert_equal [640,360],info["streams"].first.values_at("width","height")
            hashes=IO.popen(["ffmpeg","-v","error","-i",file.path,"-f","framemd5","-"],&:read).lines.reject { |line| line.start_with?("#") }.map { |line| line.split(",").last }
            assert_operator hashes.uniq.length,:>,1
            FileUtils.cp(file.path,ENV["STUDIO_NATIVE_PROOF_VIDEO"]) if ENV["STUDIO_NATIVE_PROOF_VIDEO"]
          end
          assert_equal "lightek_2d",operation.metadata.dig("layered_metrics","engine")
          assert_raises(ArgumentError) { action("artifact_reuse",project_id:@project.id,artifact_id:artifact.id) }
          assert_equal artifact.id,rpc(operation,"tools/call",{name:"studio_result",arguments:{}})[1].dig("result","structuredContent","artifact_id")
        end
      end
    end
  end
  def test_optional_blender_handoff_rejects_previews_and_unavailable_workers
    at_root do
      assert_raises(ArgumentError) { workflow(blender_handoff:true) }
      assert_raises(ArgumentError) { workflow(blender_handoff:"yes") }
      Studio::NativeBlender::Runtime.stub(:status,{ready:false}) do
        assert_raises(ArgumentError) { action("workflow_quote",scene_id:@scene.id,composition:graph,blender_handoff:true,request_key:"unavailable-blender") }
      end
      assert_empty StudioOperation.where(capability:Studio::Workflows::Production::CAPABILITY)
    end
  end
  def test_real_paid_blender_handoff_has_packed_editable_planes_and_animation
    skip "Set LIGHTEK_TEST_BLENDER=1 for the optional project handoff" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    at_root do
      composition=Studio::Workflows::ScenePlan.parse("A nighttime park with a character sitting on a bench and a gentle breeze",seed:42)
      composition["canvas"].merge!("duration"=>2,"fps"=>12)
      quote=->(operation:,**_) { operation.update!(cost_quote:{"principal_cents"=>500,"total_cents"=>550},status:"awaiting_payment") }
      result=Studio::Billing::Quote.stub(:call,quote) do
        action("workflow_quote",scene_id:@scene.id,composition:composition,blender_handoff:true,request_key:"blender-final-123")
      end
      operation=StudioOperation.find(result[:operation_id])
      assert_raises(ArgumentError) { Studio::Workflows::Production.enqueue(operation) }
      payment=DymondBank::Transaction.create!(payable:operation,status:"succeeded",amount_cents:550)
      operation.payment_succeeded!(payment)
      ExecuteStudioOperationJob.perform_now(operation.id)
      assert_equal "completed",operation.reload.status,operation.error_message
      blend=operation.artifacts.find_by!(kind:"blend")
      blend.file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"inspect-handoff.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          scene=bpy.context.scene
          planes=[obj for obj in scene.objects if obj.type=='MESH']
          assert len(planes)==#{Studio::Layered::Composition.flatten(composition).length}
          assert all(obj.get('lightek_node_id') and obj.get('lightek_asset_key') for obj in planes)
          assert all(image.packed_file for image in bpy.data.images if image.type=='IMAGE')
          assert bpy.data.texts['Lightek scene graph.json'].use_module is False
          assert any(obj.parent and obj.parent.type=='EMPTY' for obj in planes)
          tree=next(obj for obj in planes if obj.get('lightek_asset_key')=='tree.oak')
          scene.frame_set(1);start=tree.location.copy();scene.frame_set(7)
          assert (tree.location-start).length>0.0001
          assert [scene.render.resolution_x,scene.render.resolution_y,scene.frame_end]==[640,360,24]
          scene.frame_set(1);scene.cycles.samples=1;scene.render.resolution_percentage=25
          from pathlib import Path
          import struct
          preview=Path(__file__).with_suffix('.png');scene.render.filepath=str(preview)
          bpy.ops.render.render(write_still=True)
          data=preview.read_bytes();assert data.startswith(bytes([137,80,78,71,13,10,26,10]))
          assert struct.unpack('>II',data[16:24])==(160,90)
          print('LIGHTEK_HANDOFF_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"LIGHTEK_HANDOFF_VERIFIED"
        FileUtils.cp(file.path,ENV["STUDIO_NATIVE_PROOF_BLEND"]) if ENV["STUDIO_NATIVE_PROOF_BLEND"]
      end
      assert operation.artifacts.exists?(kind:"video")
    end
  end
  def test_final_export_uses_shared_quote_and_rejects_unpaid_execution
    at_root do
      quote=lambda do |operation:,**_|
        operation.update!(cost_quote:{"principal_cents"=>500,"total_cents"=>550,"rail"=>"stripe_card","context"=>"studio_render"},status:"awaiting_payment")
      end
      result=Studio::Billing::Quote.stub(:call,quote) { action("workflow_quote",scene_id:@scene.id,composition:graph,request_key:"native-final-123") }
      operation=StudioOperation.find(result[:operation_id])
      assert_equal "awaiting_payment",operation.status
      assert result[:quote]
      assert_raises(ArgumentError) { Studio::Workflows::Production.enqueue(operation) }
      assert_empty operation.artifacts
      payment=DymondBank::Transaction.create!(payable:operation,status:"succeeded",amount_cents:550)
      before=ActiveJob::Base.queue_adapter.enqueued_jobs.count
      operation.payment_succeeded!(payment)
      operation.payment_succeeded!(payment)
      assert_equal before+1,ActiveJob::Base.queue_adapter.enqueued_jobs.count

      ExecuteStudioOperationJob.perform_now(operation.id)
      assert_equal "completed",operation.reload.status,operation.error_message
      artifact=operation.artifacts.find_by!(kind:"video")
      assert action("artifact_reuse",project_id:@project.id,artifact_id:artifact.id)[:asset_id]
    end
  end
end
