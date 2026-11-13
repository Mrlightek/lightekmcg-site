module Gatekeeper
  module Hosting
    class Access
      class Denied < StandardError; end
      def self.super_admin?(actor) = actor&.persisted? && actor.role == "super_admin"

      def self.nodes(actor)
        raise Denied, "Sign in to manage servers" unless actor&.persisted?
        return GatekeeperNode.all if super_admin?(actor)
        GatekeeperNode.where(owner_type: "User", owner_id: account_ids(actor)).or(GatekeeperNode.where(id: directory_node_ids(actor,"read")))
      end

      def self.authorize!(actor, node)
        raise Denied, "This server belongs to another account" unless super_admin?(actor) ||
          (actor&.persisted? && node.owner_type == "User" && (account_ids(actor).include?(node.owner_id) || directory_node_ids(actor,"manage").include?(node.id)))
      end

      def self.directory_node_ids(actor, permission)
        defined?(LightekIdentity::ResourceGrant) ? LightekIdentity::Permissions.ids(actor,'GatekeeperNode',permission) : []
      end

      def self.account_ids(actor)
        actor.respond_to?(:managed_account_ids) ? actor.managed_account_ids : [actor.id]
      end

      def self.manages?(actor, owner)
        super_admin?(actor) || (actor&.persisted? && account_ids(actor).include?(owner.id))
      end

      def self.active!(node)
        raise Denied, "Server is unavailable or pending deletion" if %w[decommissioned deleting delete_failed provisioning].include?(node.status)
      end

      def self.site_limit(owner)
        return Float::INFINITY if super_admin?(owner)
        subscriptions = DymondBank::Subscription.where(subscriber_type: "User", subscriber_id: account_ids(owner), status: %w[active trialing])
          .where("current_period_start <= ? AND current_period_end > ?", Time.current, Time.current)
        subscriptions = subscriptions.select { |subscription| subscription.status != "trialing" ||
          (subscription.trial_ends_at && subscription.trial_ends_at > Time.current) }
        allowances = SubscriptionInfrastructureEntitlement.where(subscription_plan_id: subscriptions.map(&:plan_id)).pluck(:subscription_plan_id, :max_sites).to_h
        subscriptions.sum { |subscription| allowances.fetch(subscription.plan_id, 0).to_i }
      end

      def self.site_domains(owner)
        ids = account_ids(owner)
        nodes = GatekeeperNode.where(owner_type: "User", owner_id: ids).where.not(status: "decommissioned")
        values = GatekeeperProject.where(gatekeeper_node_id: nodes.select(:id)).pluck(:domain)
        values += GatekeeperApplicationLaunch.where(owner_id: ids).where.not(status: "deleted").pluck(:domain)
        values += GatekeeperHostedApplication.where(owner_id: ids).where.not(status: "deleted").pluck(:domain)
        if defined?(DymondSite::Site)
          values += DymondSite::Site.where(tenant_type: "User", tenant_id: ids).pluck(:host, :manifest).reject { |_, manifest| manifest.to_h["network_ledger"] == true }.map(&:first)
        end
        values.compact.map(&:downcase).uniq
      end

      def self.enforce_limit!(actor:, owner:, additional:)
        return if super_admin?(actor)
        raise Denied, "Choose an account you manage" unless manages?(actor, owner)
        account = actor.respond_to?(:white_label?) && actor.white_label? ? actor : owner
        limit = site_limit(account)
        raise Denied, "Your plan allows #{limit} sites. Change your plan to add another application." if site_domains(account).size + additional > limit
      end
    end
  end
end
