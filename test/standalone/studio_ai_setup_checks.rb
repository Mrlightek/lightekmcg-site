# Focused persistence and authorization tests; host transport and Vault are boundary fakes.
require_relative "studio_ai_checks"
require File.join(ROOT,"app/services/gatekeeper/hosting/access")
require File.join(ROOT,"app/services/gatekeeper/fleet/transport")
require File.join(ROOT,"app/jobs/studio_ai_install_job")
ActiveRecord::Schema.define do
  create_table(:genesis_test_nodes){|t|t.string :owner_type;t.integer :owner_id;t.string :status}
  create_table(:genesis_test_installations){|t|t.integer :gatekeeper_node_id;t.integer :account_id;t.string :component;t.string :domain;t.string :adapter}
  create_table(:genesis_test_secrets){|t|t.string :slug}
end
class GatekeeperNode < ApplicationRecord
  self.table_name="genesis_test_nodes"
end
class GatekeeperInstallation < ApplicationRecord
  self.table_name="genesis_test_installations"
  belongs_to :account,class_name:"User"
  belongs_to :gatekeeper_node
end
module LightekVault
  class Secret < ApplicationRecord
    self.table_name="genesis_test_secrets"
  end
  class Service
    class << self;attr_accessor :values;end
    def self.store!(slug:,payload:,**)
      Secret.create!(slug:slug);values[slug]=payload.deep_dup
    end
    def self.checkout!(slug:,requested_by:,**)=values.fetch(slug).deep_dup
  end
end
class StudioAiSetupTest < StudioAiTest
  StudioAiTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def setup
    super
    GatekeeperInstallation.delete_all;GatekeeperNode.delete_all;LightekVault::Secret.delete_all;LightekVault::Service.values={}
    @alice.update!(role:"member");@site.update!(tenant:@alice)
    @node=GatekeeperNode.create!(owner_type:"User",owner_id:@alice.id,status:"ready")
    @worker=GatekeeperInstallation.create!(gatekeeper_node:@node,account:@alice,component:"lightek_app",adapter:"native_rails",domain:"worker.example.test")
    FileUtils.cp(File.join(ROOT,"config/studio_ai/packages.json"),Rails.root.join("config/studio_ai/packages.json"))
  end
  def install(**extra)=action("ai_setup_install",scene_id:@scene.id,installation_id:@worker.id,package_id:"concept",device:"cpu",**extra)
  def fake_receipt(args)
    p=args.fetch(:payload)
    p.transform_keys(&:to_s).except("api_token","action").merge("status"=>"ready")
  end
  def test_setup_is_scoped_idempotent_and_rejects_unsupported_packages
    other=GatekeeperInstallation.create!(gatekeeper_node:@node,account:@bob,component:"lightek_app",adapter:"native_rails",domain:"other.example.test")
    assert_raises(ActiveRecord::RecordNotFound){install(installation_id:other.id)}
    assert_raises(ArgumentError){install(package_id:"video",device:"cpu")}
    before=ActiveJob::Base.queue_adapter.enqueued_jobs.count{|j|j[:job]==StudioAiInstallJob}
    first=install;second=install
    assert_equal first["request_id"],second["request_id"]
    assert_equal before+1,ActiveJob::Base.queue_adapter.enqueued_jobs.count{|j|j[:job]==StudioAiInstallJob}
    assert_raises(ArgumentError){install(device:"cuda")}
    assert_raises(ArgumentError){generate}
    assert_empty StudioAsset.where(site_id:@site.id)
  end
  def test_setup_node_management_is_required_even_with_website_access
    @node.update!(owner_id:@bob.id)
    assert_raises(ActiveRecord::RecordNotFound){install}
    @node.update!(owner_id:@alice.id,status:"deleting")
    assert_raises(Gatekeeper::Hosting::Access::Denied){install}
  end
  def test_setup_waits_for_generation_and_local_job_keeps_original_worker
    asset=StudioAsset.find(generate[:asset_id])
    assert_equal({"mode"=>"local"},asset.metadata["ai_worker"])
    assert_raises(ArgumentError){install}
    asset.update!(status:"ready")
    state=install
    calls=[]
    Gatekeeper::Fleet::Transport.stub(:run!,->(**args){calls<<args.deep_dup;fake_receipt(args)}) do
      StudioAiInstallJob.perform_now(@site.id,@alice.id,state["request_id"])
      StudioAiInstallJob.perform_now(@site.id,@alice.id,state["request_id"])
    end
    assert_equal 1,calls.length
    assert_equal "install_studio_ai.py",calls[0][:script_name]
    assert_match(/\A[a-f0-9]{64}\z/,calls[0][:payload][:api_token])
    assert_equal "ready",@site.reload.manifest.dig("studio_ai_install","status")
    refute_includes JSON.generate(@site.manifest),calls[0][:payload][:api_token]
    asset.update!(status:"uploaded");StudioAiGenerationJob.perform_now(asset.id)
    assert_equal 1,@submitted.size # Still the original loopback engine.
  end
  def test_setup_failed_install_retains_existing_worker_and_retry_credentials
    @site.update!(manifest:{"studio_ai_worker"=>{"site_id"=>@site.id,"installation_id"=>@worker.id}})
    state=install
    Gatekeeper::Fleet::Transport.stub(:run!,->(**_){raise Gatekeeper::Fleet::Transport::RemoteFailure.new({"reason"=>"insufficient_memory"})}) do
      assert_raises(Gatekeeper::Fleet::Transport::RemoteFailure){StudioAiInstallJob.perform_now(@site.id,@alice.id,state["request_id"])}
    end
    assert_equal @worker.id,@site.reload.manifest.dig("studio_ai_worker","installation_id")
    assert_match(/RAM/,@site.manifest.dig("studio_ai_install","message"))
    slug=Studio::Ai::Setup.slug(@site.id,@worker.id);token=LightekVault::Service.values.fetch(slug)["token"]
    retry_state=install
    refute_equal state["request_id"],retry_state["request_id"]
    Gatekeeper::Fleet::Transport.stub(:run!,->(**args){assert_equal token,args[:payload][:api_token];fake_receipt(args)}){StudioAiInstallJob.perform_now(@site.id,@alice.id,retry_state["request_id"])}
    assert_equal 1,LightekVault::Secret.count
  end
  def test_setup_status_only_reports_real_server_bytes_and_recovers_interruption
    state=install;@site.reload.update!(manifest:@site.manifest.merge("studio_ai_install"=>state.merge("status"=>"running")))
    Gatekeeper::Fleet::Transport.stub(:run!,->(**args){assert_equal "status",args[:payload][:action];{"phase"=>"downloading_model","downloaded_bytes"=>42,"total_bytes"=>100,"api_token"=>"must-not-leak"}}) do
      result=action("ai_setup_status",scene_id:@scene.id)
      assert_equal 42,result[:install]["downloaded_bytes"]
      refute_includes JSON.generate(result),"must-not-leak"
    end
    @site.reload.update!(manifest:@site.manifest.merge("studio_ai_install"=>state.merge("status"=>"running","started_at"=>131.minutes.ago.iso8601)))
    result=action("ai_setup_status",scene_id:@scene.id)
    assert_equal "failed",result[:install]["status"]
    refute Studio::Ai::Setup.pending?(@site.reload)
  end
  def test_setup_remote_origin_is_derived_and_cross_account_worker_rejected
    slug=Studio::Ai::Setup.slug(@site.id,@worker.id)
    LightekVault::Service.store!(slug:slug,payload:{"url"=>"https://worker.example.test/lightek-ai","token"=>"a"*64})
    identity={"site_id"=>@site.id,"installation_id"=>@worker.id}
    runtime=Studio::Ai::Runtime.new(site:@site,identity:identity)
    requests=[]
    http=Object.new
    http.define_singleton_method(:request){|request,&block|requests<<request;response=Net::HTTPOK.new("1.1","200","OK");response.define_singleton_method(:read_body){|&b|b.call('{}')};block.call(response)}
    Net::HTTP.stub(:start,->(*args,**options,&block){assert_equal "worker.example.test",args.first;assert options[:use_ssl];block.call(http)}) do
      runtime.json("/object_info");runtime.request("/view?filename=test.png")
    end
    assert_equal "/lightek-ai/object_info",requests.first.path
    assert_equal "Bearer #{'a'*64}",requests.first["Authorization"]
    assert_equal "/lightek-ai/view?filename=test.png",requests.last.path
    assert_raises(ArgumentError){Studio::Ai::Runtime.new(site:@site,identity:identity.merge("site_id"=>@other_site.id))}
    @worker.update!(account:@bob)
    assert_raises(ArgumentError){Studio::Ai::Runtime.new(site:@site,identity:identity)}
  end
  def test_setup_read_only_server_grant_cannot_install_and_has_no_setup_controls
    @node.update!(owner_id:@bob.id)
    Gatekeeper::Hosting::Access.stub(:nodes,GatekeeperNode.all) do
      assert_raises(Gatekeeper::Hosting::Access::Denied){install}
      assert_empty action("ai_setup_status",scene_id:@scene.id)[:workers]
    end
  end
  def test_setup_invalid_receipt_never_selects_an_unverified_worker
    state=install
    Gatekeeper::Fleet::Transport.stub(:run!,->(**args){fake_receipt(args).merge("request_id"=>"someone-else")}) do
      assert_raises(ArgumentError){StudioAiInstallJob.perform_now(@site.id,@alice.id,state["request_id"])}
    end
    assert_equal "failed",@site.reload.manifest.dig("studio_ai_install","status")
    assert_nil @site.manifest["studio_ai_worker"]
  end
  def test_setup_video_recipe_requires_all_three_actual_model_inventories
    FileUtils.cp(File.join(ROOT,"config/studio_ai/workflows/wan22_video.json"),Rails.root.join("config/studio_ai/workflows/wan22_video.json"))
    recipe=JSON.parse(File.read(File.join(ROOT,"config/studio_ai/workflows/wan22_video.json")))
    nodes=recipe["workflow"].values.to_h{|n|[n["class_type"],{}]}
    recipe["required_models"].each{|spec|nodes[spec["node"]]={"input"=>{"required"=>{spec["field"]=>[[spec["name"]]]}}}}
    runtime=Studio::Ai::Runtime.new
    runtime.stub(:json,nodes) do
      assert runtime.inventory[:recipes].find{|r|r[:id]=="wan22_video"}[:ready]
      nodes["VAELoader"]["input"]["required"]["vae_name"]=[[]]
      refute runtime.inventory[:recipes].find{|r|r[:id]=="wan22_video"}[:ready]
    end
  end
end
