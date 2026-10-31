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

      payload =
        params
          .fetch(:payload, {})
          .to_unsafe_h

      subject =
        resolve_subject(
          params[:subject]
        )

      event_type =
        resolve_event_type!(
          capability
        )

      worker_action =
        resolve_worker_action!(
          capability
        )

      payload["user_id"] = actor.id
      if capability.start_with?("community.", "studio.", "social.", "messaging.", "messages.", "susu.", "money.")
        payload["site_id"] = LightekPwa::SiteContext.resolve(request.host).id
        payload["origin"] = request.base_url
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

      result =
        ::Nevaeh.handle(
          event_type: event_type,
          source: "lightek_pwa",
          subject: subject,
          actor: actor,

          payload: payload,

          context: {
            "client" => "lightek_pwa",
            "capability" => capability
          },

          args: [
            worker_action,
            payload
          ],

          correlation_id:
            correlation_id
        )

      work_item =
        result.work_item

            # Dispatch owns execution.
      # The controller only waits briefly for short
      # request/response capabilities to finish.
      deadline =
        Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        ) + 5.0

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
    rescue ActionController::ParameterMissing,
           ActiveRecord::RecordNotFound,
           ArgumentError,
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
        status: work_item.done? ? "completed" : work_item.status,
        work_item_id: work_item.id, result: work_item.done? ? authorized_receipt_result(work_item.result, arguments) : nil,
        error: work_item.failed? ? work_item.error : nil
      }, status: work_item.finished? ? :ok : :accepted
    end

    private

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

    def community_action(slug)
      LightekCommunity::Workers::Pwa::ACTIONS.find do |action|
        slug == "community.#{action.delete_prefix('community_').tr('_', '.')}"
      end
    end

    def workspace_action(slug)
      ::Studio::Workers::Workspace::ACTIONS.find { |action| slug == "studio.workspace.#{action.tr('_', '.')}" }
    end

    def resolve_event_type!(slug)
      return "#{slug}.requested" if community_action(slug) || workspace_action(slug)
      {
        "studio.scene_object.destroy" =>
          "studio.scene_object.destroy.requested",

        "studio.scene_object.duplicate" =>
          "studio.scene_object.duplicate.requested",

        "studio.scene_object.transform" =>
          "studio.scene_object.transform.requested",

        "studio.scene_object.create" =>
          "studio.scene_object.create.requested",

        "studio.project.create" =>
          "studio.project.create.requested",

        "studio.pwa.bootstrap" =>
          "studio.pwa.bootstrap.requested",

        "susu.list" =>
          "susu.list.requested",

        "susu.show" =>
          "susu.show.requested",

        "susu.contribution.quote" =>
          "susu.contribution.quote.requested",

        "susu.contribution.checkout" =>
          "susu.contribution.checkout.requested",

        "messages.people" =>
          "messages.people.requested",

        "messages.list" =>
          "messages.list.requested",

        "messages.show" =>
          "messages.show.requested",

        "messages.start" =>
          "messages.start.requested",

        "messages.send" =>
          "messages.send.requested",

        "messages.delete" =>
          "messages.delete.requested",

        "messages.leave" =>
          "messages.leave.requested",

        "messages.group.add_members" =>
          "messages.group.add_members.requested",

        "messages.group.remove_member" =>
          "messages.group.remove_member.requested",

        "messages.group.promote_admin" =>
          "messages.group.promote_admin.requested",

        "messages.group.demote_admin" =>
          "messages.group.demote_admin.requested",

        "messages.mark_read" =>
          "messages.mark_read.requested",

        "social.people.recommend" =>
          "social.people.recommend.requested",

        "social.relationship.context" =>
          "social.relationship.context.requested",

        "social.connection.opportunities" =>
          "social.connection.opportunities.requested",

        "social.follow" =>
          "social.follow.requested",

        "social.unfollow" =>
          "social.unfollow.requested",

        "social.blocks.list" =>
          "social.blocks.list.requested",

        "social.unblock" =>
          "social.unblock.requested",

        "social.friendship.request" =>
          "social.friendship.request.requested",

        "social.friendship.respond" =>
          "social.friendship.respond.requested",

        "social.friendship.end" =>
          "social.friendship.end.requested",

        "social.block" =>
          "social.block.requested"
      }.fetch(slug) {
        raise ArgumentError,
              "Unsupported capability: #{slug}"
      }
    end

    def resolve_worker_action!(slug)
      action = community_action(slug) || workspace_action(slug)
      return action if action
      {
        "studio.scene_object.destroy" =>
          "destroy",

        "studio.scene_object.duplicate" =>
          "duplicate",

        "studio.scene_object.transform" =>
          "transform",

        "studio.scene_object.create" =>
          "create",

        "studio.project.create" =>
          "create",

        "studio.pwa.bootstrap" =>
          "bootstrap",

        "susu.list" =>
          "list",

        "susu.show" =>
          "show",

        "susu.contribution.quote" =>
          "contribution_quote",

        "susu.contribution.checkout" =>
          "contribution_checkout",

        "messages.people" =>
          "people",

        "messages.list" =>
          "list",

        "messages.show" =>
          "show",

        "messages.start" =>
          "start",

        "messages.send" =>
          "send",

        "messages.delete" =>
          "delete",

        "messages.leave" =>
          "leave",

        "messages.group.add_members" =>
          "group_add_members",

        "messages.group.remove_member" =>
          "group_remove_member",

        "messages.group.promote_admin" =>
          "group_promote_admin",

        "messages.group.demote_admin" =>
          "group_demote_admin",

        "messages.mark_read" =>
          "mark_read",

        "social.people.recommend" =>
          "people_recommend",

        "social.relationship.context" =>
          "relationship_context",

        "social.connection.opportunities" =>
          "connection_opportunities",

        "social.follow" =>
          "follow",

        "social.unfollow" =>
          "unfollow",

        "social.blocks.list" =>
          "blocks_list",

        "social.unblock" =>
          "unblock",

        "social.friendship.request" =>
          "friendship_request",

        "social.friendship.respond" =>
          "friendship_respond",

        "social.friendship.end" =>
          "friendship_end",

        "social.block" =>
          "block"
      }.fetch(slug)
    end
  end
end
