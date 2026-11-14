# frozen_string_literal: true
module Studio
  module Ai
    class Setup
      CONSUMER = "Studio::Ai::Runtime"
      PURPOSE = "studio_ai"
      ACTIVE = %w[queued running].freeze
      def self.catalog = JSON.parse(Rails.root.join("config/studio_ai/packages.json").read)
      def self.slug(site_id, installation_id) = "studio-ai-#{site_id}-#{installation_id}"
      def self.installations(site:, actor:)
        GatekeeperInstallation.where(account:site.tenant, component:"lightek_app", adapter:%w[native_rails docker_compose],
          gatekeeper_node_id: ::Gatekeeper::Hosting::Access.nodes(actor).select(:id))
      end
      def self.site_for(access, scene_id)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        DymondSite::Site.find(access.site_id)
      end
      def self.pending?(site) = ACTIVE.include?(site.manifest.to_h.dig("studio_ai_install","status"))
      def self.busy?(site)
        StudioAsset.where(site_id:site.id,status:%w[uploaded processing]).where("metadata ->> 'ai_intent' IS NOT NULL").exists?
      end
      def self.start(access:, payload:)
        site=site_for(access,payload.fetch("scene_id"))
        installation=installations(site:site,actor:access.user).find(payload.fetch("installation_id"))
        ::Gatekeeper::Hosting::Access.authorize!(access.user,installation.gatekeeper_node)
        ::Gatekeeper::Hosting::Access.active!(installation.gatekeeper_node)
        package=catalog.fetch("packages")[payload["package_id"].to_s]
        raise ArgumentError,"Choose an installed worker package and supported device" unless package && package["devices"].include?(payload["device"])
        site.with_lock do
          previous=site.manifest.to_h["studio_ai_install"].to_h
          if ACTIVE.include?(previous["status"])
            same=previous.values_at("installation_id","package_id","device")==[installation.id,payload["package_id"],payload["device"]]
            raise ArgumentError,"Worker setup is already running" unless same
            return previous.slice("status","request_id","installation_id","package_id","device")
          end
          raise ArgumentError,"Wait for active generations to finish before changing the worker" if busy?(site)
          state={"status"=>"queued","request_id"=>SecureRandom.uuid,"installation_id"=>installation.id,
            "package_id"=>payload["package_id"],"device"=>payload["device"],"started_at"=>Time.current.iso8601}
          site.update!(manifest:site.manifest.to_h.merge("studio_ai_install"=>state))
          StudioAiInstallJob.perform_later(site.id,access.user.id,state["request_id"])
          state
        end
      end
      def self.status(access:, payload:)
        site=site_for(access,payload.fetch("scene_id"));state=site.manifest.to_h["studio_ai_install"].to_h
        if ACTIVE.include?(state["status"]) && Time.iso8601(state.fetch("started_at"))<130.minutes.ago
          site.with_lock do
            current=site.manifest.to_h["studio_ai_install"].to_h
            if current["request_id"]==state["request_id"] && ACTIVE.include?(current["status"]) && Time.iso8601(current.fetch("started_at"))<130.minutes.ago
              state=current.merge("status"=>"failed","message"=>"Setup was interrupted or exceeded its two-hour limit. Check the worker, then retry.")
              site.update!(manifest:site.manifest.to_h.merge("studio_ai_install"=>state))
            end
          end
        end
        targets=installations(site:site,actor:access.user).select do |installation|
          begin
            ::Gatekeeper::Hosting::Access.authorize!(access.user,installation.gatekeeper_node)
            ::Gatekeeper::Hosting::Access.active!(installation.gatekeeper_node)
            true
          rescue ::Gatekeeper::Hosting::Access::Denied
            false
          end
        end
        target=targets.find{|i|i.id==state["installation_id"]}
        if target && state["status"]=="running"
          begin
            remote=transport(site,target,state,access.user,action:"status")
            state=state.merge(remote.slice("phase","model","downloaded_bytes","total_bytes"))
          rescue StandardError
            state=state.merge("progress_message"=>"Server progress is temporarily unavailable. Setup may still be running.")
          end
        end
        {install:state.slice("status","request_id","installation_id","package_id","device","phase","model","downloaded_bytes","total_bytes","message","progress_message"),
          workers:targets.map{|i|{id:i.id,domain:i.domain}},
          packages:catalog.fetch("packages").map{|id,p|{id:id,name:p["name"],devices:p["devices"],ram_gib:p["ram_gib"],free_disk_gib:p["free_disk_gib"],vram_mib:p["vram_mib"]}},
          active:site.manifest.to_h["studio_ai_worker"].present?}
      end
      def self.transport(site, installation, state, actor, action:, token:nil)
        ::Gatekeeper::Fleet::Transport.run!(node:installation.gatekeeper_node,domain:installation.domain,requested_by:actor.email_address,
          operation_id:nil,script_name:"install_studio_ai.py",payload:{action:action,domain:installation.domain,owner_domain:site.host,
            request_id:state.fetch("request_id"),package_id:state["package_id"],device:state["device"],api_token:token})
      end
      # Identity is saved with each asset. URLs and Vault paths never come from the browser.
      def self.connection(site, identity)
        raise ArgumentError,"Invalid generation worker identity" unless identity.is_a?(Hash) && identity["site_id"]==site.id
        installation=GatekeeperInstallation.find(identity.fetch("installation_id"))
        raise ArgumentError,"Generation worker no longer belongs to this account" unless installation.account==site.tenant && installation.component=="lightek_app"
        secret=LightekVault::Service.checkout!(slug:slug(site.id,installation.id),consumer:CONSUMER,purpose:PURPOSE,requested_by:"Studio generation / site #{site.id}")
        expected="https://#{installation.domain}/lightek-ai"
        raise ArgumentError,"Invalid generation worker credential" unless secret["url"]==expected && secret["token"].to_s.match?(/\A[a-f0-9]{64}\z/)
        [expected,secret.fetch("token")]
      end
    end
  end
end
