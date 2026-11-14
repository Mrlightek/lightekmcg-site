# frozen_string_literal: true
class StudioAiInstallJob < ApplicationJob
  queue_as :default
  # Never automatically repeat a host mutation after an interrupted invocation.
  def perform(site_id, actor_id, request_id)
    site=DymondSite::Site.find(site_id);actor=User.find(actor_id);state=nil
    site.with_lock do
      state=site.manifest.to_h["studio_ai_install"].to_h
      return unless state["request_id"]==request_id && state["status"]=="queued"
      state=state.merge("status"=>"running","started_at"=>Time.current.iso8601)
      site.update!(manifest:site.manifest.to_h.merge("studio_ai_install"=>state))
    end
    installation=Studio::Ai::Setup.installations(site:site,actor:actor).find(state.fetch("installation_id"))
    Gatekeeper::Hosting::Access.authorize!(actor,installation.gatekeeper_node)
    Gatekeeper::Hosting::Access.active!(installation.gatekeeper_node)
    slug=Studio::Ai::Setup.slug(site.id,installation.id)
    unless LightekVault::Secret.exists?(slug:slug)
      LightekVault::Service.store!(name:"Genesis worker · #{site.id}/#{installation.id}",slug:slug,
        payload:{"url"=>"https://#{installation.domain}/lightek-ai","token"=>SecureRandom.hex(32)},
        provider:"comfyui",purpose:Studio::Ai::Setup::PURPOSE,requested_by:actor.email_address,
        access_policy:{"consumers"=>[Studio::Ai::Setup::CONSUMER,self.class.name],"purposes"=>[Studio::Ai::Setup::PURPOSE]})
    end
    secret=LightekVault::Service.checkout!(slug:slug,consumer:self.class.name,purpose:Studio::Ai::Setup::PURPOSE,requested_by:actor.email_address)
    receipt=Studio::Ai::Setup.transport(site,installation,state,actor,action:"install",token:secret.fetch("token"))
    raise ArgumentError,"Invalid worker setup receipt" unless receipt.values_at("status","request_id","domain","owner_domain","package_id","device")==["ready",request_id,installation.domain,site.host,state["package_id"],state["device"]]
    site.with_lock do
      return unless site.manifest.to_h.dig("studio_ai_install","request_id")==request_id
      site.update!(manifest:site.manifest.to_h.merge("studio_ai_install"=>state.merge("status"=>"ready","phase"=>"ready","verified_at"=>Time.current.iso8601),
        "studio_ai_worker"=>{"site_id"=>site.id,"installation_id"=>installation.id}))
    end
  rescue StandardError=>error
    message=if error.is_a?(Gatekeeper::Fleet::Transport::RemoteFailure)
      {"insufficient_memory"=>"This package needs more total and available RAM. Use a larger worker and retry.",
       "insufficient_disk"=>"This worker needs more free disk for the engine and models.","gpu_required"=>"Choose a CUDA worker for this package.",
       "gpu_unavailable"=>"An NVIDIA GPU, driver and container runtime must be ready on this worker.","insufficient_vram"=>"This package needs a GPU with more video memory.",
       "https_vhost_required"=>"The worker needs one active HTTPS website configuration.","worker_assigned_elsewhere"=>"This worker is already assigned to another website.",
       "installation_busy"=>"Another setup is running on this worker. Wait for it to finish.","model_checksum_mismatch"=>"Model verification failed. Retry to download the model again.",
       "engine_health_failed"=>"The engine did not become healthy. Check worker capacity and its HTTPS connection."}[error.receipt["reason"]]
    end
    site&.with_lock do
      current=site.manifest.to_h["studio_ai_install"].to_h
      if current["request_id"]==request_id
        site.update!(manifest:site.manifest.to_h.merge("studio_ai_install"=>current.merge("status"=>"failed","message"=>message || "Setup could not finish. Check the worker connection and retry.")))
      end
    end
    raise
  ensure
    secret&.each_value{|v|v.clear if v.is_a?(String) && !v.frozen?}
  end
end
