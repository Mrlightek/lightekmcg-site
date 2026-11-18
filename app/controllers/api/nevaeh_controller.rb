module Api
  class NevaehController < ApplicationController
    allow_unauthenticated_access only: :bootstrap
    protect_from_forgery with: :exception
    before_action { response.set_header("Cache-Control", "private, no-store") }
    rescue_from LightekPwa::Policy::Denied do |error|
      render json: {status: "failed", error: error.message}, status: :forbidden
    end

    def bootstrap
      payload =
        LightekPwa::Bootstrap.new(
          user: resolved_current_user,
          site: LightekPwa::SiteContext.resolve(request.host)
        ).call

      payload =
        payload.merge(
          csrf_token: form_authenticity_token
        )

      render json: payload
    end

    def execute
      actor =
        resolved_current_user

      unless actor
        render json: {
          status: "failed",
          error: "Authentication required"
        }, status: :unauthorized

        return
      end

      capability =
        params
          .require(:capability)
          .to_s

      raw_payload=params[:payload]
      raise ArgumentError,"Use a JSON object for action inputs" if raw_payload && !raw_payload.respond_to?(:to_unsafe_h)
      payload=raw_payload ? raw_payload.to_unsafe_h : {}

      subject =
        resolve_subject(
          params[:subject]
        )

      if capability == "nevaeh.conversation"
        return studio_conversation(actor,payload)
      end

      payload["user_id"] = actor.id
      if capability.start_with?("community.", "studio.", "social.", "messaging.", "messages.", "susu.", "money.")
        payload["site_id"] = LightekPwa::SiteContext.resolve(request.host).id
        payload["origin"] = request.base_url
        if capability.start_with?("studio.")
          LightekPwa::Network.require_studio_write!(user: actor, site: LightekPwa::SiteContext.resolve(request.host), capability: capability)
        end
        LightekPwa::Policy.new(user: actor, site: LightekPwa::SiteContext.resolve(request.host)).authorize_capability!(capability)
      end

      if capability ==
         "susu.contribution.checkout"

        return_url =
          "#{request.base_url}" \
          "/lightek/index.html#/susu"

        payload["success_url"] ||=
          return_url

        payload["cancel_url"] ||=
          return_url
      end

      if subject.is_a?(SusuGroup)
        payload["group_id"] =
          subject.id
      end

      correlation_id =
        if defined?(
          NevaehOrchestration::Correlation
        )
          NevaehOrchestration::Correlation
            .generate
        else
          SecureRandom.uuid
        end

      result = conversation(actor).execute_native(capability:capability,payload:payload,source:"lightek_pwa",
        subject:subject,context:{"client"=>"lightek_pwa"},correlation_id:correlation_id)

      work_item =
        result.work_item

            # Dispatch owns execution.
      # The controller only waits briefly for short
      # request/response capabilities to finish.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (params[:prefer_async] == true ? 0 : 5.0)

      loop do
        work_item.reload

        break if work_item.finished?

        now =
          Process.clock_gettime(
            Process::CLOCK_MONOTONIC
          )

        break if now >= deadline

        sleep 0.05
      end

      work_item.reload


      if work_item.done?
        render json: {
          capability: capability,
          status: "completed",
          correlation_id:
            correlation_id,
          work_item_id:
            work_item.id,
          result:
            work_item.result
        }
      elsif work_item.failed?
        render json: {
          capability: capability,
          status: "failed",
          correlation_id:
            correlation_id,
          work_item_id:
            work_item.id,
          error:
            work_item.error
        }, status: :unprocessable_entity
      else
        render json: {
          capability: capability,
          status: work_item.status,
          correlation_id:
            correlation_id,
          work_item_id:
            work_item.id
        }, status: :accepted
      end
    rescue Studio::Compute::Guardrails::Limit => error
      render json:{status:"failed",error:error.message,suggestion:error.suggestion},status: :unprocessable_entity
    rescue ActionController::ParameterMissing,
           ActiveRecord::RecordNotFound,
           ArgumentError, KeyError,
           Susu::Workers::Pwa::AccessDenied,
           LightekSocial::AccessDenied,
           LightekCommunity::AccessDenied,
           ActiveRecord::RecordInvalid => error

      render json: {
        status: "failed",
        error: error.message
      }, status: :unprocessable_entity
    end

    # Read only the receipt belonging to the authenticated actor. Polling must
    # never execute or retry the job; Dispatch remains the execution owner.
    def execution
      authenticated?
      work_item = DymondDispatch::WorkItem.find(params[:id])
      arguments = Array(work_item.args)[1]
      raise ActiveRecord::RecordNotFound unless arguments.is_a?(Hash)
      owner_id = arguments["user_id"]
      raise ActiveRecord::RecordNotFound unless current_user && owner_id.to_s == current_user.id.to_s
      if arguments["site_id"].present?
        receipt_site = LightekPwa::SiteContext.resolve(request.host)
        raise ActiveRecord::RecordNotFound unless receipt_site.id.to_s == arguments["site_id"].to_s
        LightekPwa::Policy.new(user: current_user, site: receipt_site).authorize!
      end
      render json: {
        correlation_id: work_item.correlation_id,
        status: work_item.done? ? "completed" : work_item.status,
        work_item_id: work_item.id, result: work_item.done? ? authorized_receipt_result(work_item.result, arguments) : nil,
        error: work_item.failed? ? work_item.error : nil
      }, status: work_item.finished? ? :ok : :accepted
    end

    private

    def conversation(actor)
      NevaehOs::Conversation.new(actor:actor,host:request.host,origin:request.base_url)
    end

    def studio_conversation(actor,payload)
      site=LightekPwa::SiteContext.resolve(request.host)
      access=Studio::PwaAccess.new("user_id"=>actor.id,"site_id"=>site.id)
      LightekPwa::Policy.new(user:actor,site:site).authorize!("studio")
      if payload["action_id"]
        action=NevaehOsAction.where(user:actor).find(payload["action_id"])
        return render json:{status:"completed",result:NevaehOs::Receipts.for(action)}
      end
      if payload["retry_economy"]
        capability="studio.workspace.ai.generate"
        LightekPwa::Network.require_studio_write!(user:actor,site:site,capability:capability)
        inputs=Studio::Workers::Activity.retry_economy_inputs!(actor,site,payload["retry_economy"])
        id=SecureRandom.uuid
        item=conversation(actor).execute_native(capability:capability,payload:inputs,source:"lightek_pwa",correlation_id:id).work_item
        return render json:{status:"completed",result:{text:"I’ve queued an Economy retry.",work_item_id:item.id,task_uuid:id}}
      end
      if payload["teach"]
        taught=NevaehOs::TaskBuilder.teach_studio!(actor:actor,site:site,receipt_id:payload.fetch("work_item_id"),phrase:payload["teach"])
        return render json:{status:"completed",result:{text:"Shortcut saved and ready to use.",binding_id:taught.id}}
      end

      scene=access.scene!(payload.fetch("scene_id"))
      raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==site.id
      text=payload.fetch("text")
      raise ArgumentError,"Enter a message of 1–2000 characters" unless text.is_a?(String) && text.strip.length.between?(1,2000)
      view=payload.fetch("view","create")
      raise ArgumentError,"Choose a Studio workspace" unless %w[create timeline library publish].include?(view)
      asset_id=payload["asset_id"]
      asset_id=StudioAsset.for_actor(access).where(site_id:site.id).find(asset_id).id if asset_id
      artifact_id=payload["artifact_id"]
      if artifact_id
        operation=scene.studio_operations.where(status:"completed").joins(:artifacts).where(artifacts:{id:artifact_id}).first!
        artifact_id=operation.artifacts.find(artifact_id).id
      end
      context={"path"=>"/dashboard/studio-broadcasting/workspace/#{scene.id}","title"=>"Lightek Studio",
        "site_id"=>site.id,"project_id"=>scene.studio_project_id,"scene_id"=>scene.id,"studio_view"=>view,"asset_id"=>asset_id,"artifact_id"=>artifact_id}
      key=payload.fetch("request_key")
      stream=NevaehOs::ReplyStream.publisher(actor,key) if payload["stream"]==true
      reply=conversation(actor).ask(text:text,request_key:key,page_context:context,&stream)
      render json:{status:"completed",result:reply}
    end

    def authorized_receipt_result(result, arguments)
      return result unless result.is_a?(Hash) && arguments["site_id"].present?
      data = result.deep_stringify_keys
      access = LightekCommunity::Access.new(user: current_user, site_id: arguments["site_id"])
      presenter = LightekCommunity::Presenter.new(access)
      if data["post"].is_a?(Hash) && data["post"]["id"]
        data["post"] = presenter.post(access.posts.find(data["post"]["id"]))
      end
      if data["community"].is_a?(Hash) && data["community"]["slug"]
        data["community"] = presenter.community(access.community!(data["community"]["slug"]))
      end
      data
    end

    def require_authentication
      return if authenticated?
      render json: { error: "Authentication required" }, status: :unauthorized
    end

      def resolved_current_user
        if respond_to?(
          :authenticated?,
          true
        )
          authenticated?
        end

        if respond_to?(
          :current_user,
          true
        )
          current_user
        end
      end

    def resolve_subject(raw)
      data =
        raw.respond_to?(:to_unsafe_h) ?
          raw.to_unsafe_h :
          raw.to_h

      return nil if data.blank?

      type =
        data["type"].to_s

      id =
        data["id"]

      case type
      when "SusuGroup"
        SusuGroup.find(id)
      else
        raise ArgumentError,
              "Unsupported subject type: #{type}"
      end
    end

    def community_action(slug) = NevaehOrchestration::NativeContracts.community_action(slug)
    def workspace_action(slug) = NevaehOrchestration::NativeContracts.workspace_action(slug)
  end
end
