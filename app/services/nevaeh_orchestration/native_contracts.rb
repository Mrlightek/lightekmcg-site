# frozen_string_literal: true
module NevaehOrchestration
  # Shared by the PWA API and conversational OS; worker vocabulary has one source.
  module NativeContracts
    module_function
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
    def supported?(slug)
      resolve_worker_action!(slug)
      true
    rescue KeyError
      false
    end
  end
end
