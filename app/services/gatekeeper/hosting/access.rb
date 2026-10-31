module Gatekeeper
  module Hosting
    class Access
      class Denied < StandardError; end
      def self.super_admin?(actor) = actor&.persisted? && actor.role == "super_admin"

      def self.nodes(actor)
        raise Denied, "Sign in to manage servers" unless actor&.persisted?
        return GatekeeperNode.all if super_admin?(actor)
        GatekeeperNode.where(owner: actor)
      end

      def self.authorize!(actor, node)
        raise Denied, "This server belongs to another account" unless super_admin?(actor) ||
          (actor&.persisted? && node.owner_type == "User" && node.owner_id == actor.id)
      end

      def self.active!(node)
        raise Denied, "Server is unavailable or pending deletion" if %w[decommissioned deleting delete_failed provisioning].include?(node.status)
      end

      def self.site_limit(owner)
        return Float::INFINITY if super_admin?(owner)
        subscriptions = DymondBank::Subscription.where(subscriber: owner, status: %w[active trialing])
          .where("current_period_start <= ? AND current_period_end > ?", Time.current, Time.current)
        subscriptions = subscriptions.select { |subscription| subscription.status != "trialing" ||
          (subscription.trial_ends_at && subscription.trial_ends_at > Time.current) }
        SubscriptionInfrastructureEntitlement.where(subscription_plan_id: subscriptions.map(&:plan_id)).maximum(:max_sites).to_i
      end

      def self.site_domains(owner)
        nodes = GatekeeperNode.where(owner: owner).where.not(status: "decommissioned")
        values = GatekeeperProject.where(gatekeeper_node_id: nodes.select(:id)).pluck(:domain)
        values += GatekeeperHostedApplication.where(owner: owner).where.not(status: "deleted").pluck(:domain)
        values += DymondSite::Site.where(tenant: owner).pluck(:host) if defined?(DymondSite::Site)
        values.compact.map(&:downcase).uniq
      end

      def self.enforce_limit!(actor:, owner:, additional:)
        return if super_admin?(actor)
        raise Denied, "Choose an account you own" unless actor == owner
        limit = site_limit(owner)
        raise Denied, "Your plan allows #{limit} sites. Change your plan to add another application." if site_domains(owner).size + additional > limit
      end
    end
  end
end
