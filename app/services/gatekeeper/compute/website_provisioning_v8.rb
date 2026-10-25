# frozen_string_literal: true

module Gatekeeper
  module Compute
    # Creates real Dymond Site records against the existing subscription.
    # DNS, TLS and webserver activation are subsequent provisioning steps.
    class WebsiteProvisioningV8
      class NotEntitled < StandardError; end
      class HostOwnedByAnotherTenant < StandardError; end

      def self.call(subscription:, account_key:, site_name:, base_domain: "lightekmcg.com")
        new(subscription:, account_key:, site_name:, base_domain:).call
      end

      def initialize(subscription:, account_key:, site_name:, base_domain:)
        @subscription = subscription
        @account_key = account_key
        @site_name = site_name.to_s.strip
        @base_domain = base_domain
      end

      def call
        raise NotEntitled, "A persisted, active subscription is required" unless eligible?
        raise ArgumentError, "site name cannot be blank" if @site_name.blank?

        plan = ProvisioningExecutionService.website_plan_v8(
          account_key: @account_key, base_domain: @base_domain
        )
        hostname = plan.fetch("default_subdomain")

        # Subscription row serializes retries on the same purchase.
        # Site identity is bound to the actual subscriber, not a request parameter.
        @subscription.with_lock do
          site = DymondSite::Site.find_by(host: hostname)
          if site && !same_tenant?(site)
            raise HostOwnedByAnotherTenant, "Hostname belongs to another account"
          end

          site ||= DymondSite::Site.create!(
            name: @site_name,
            host: hostname,
            tenant: @subscription.subscriber
          )
          site.create_nav_menu! unless site.nav_menu
          site
        end
      end

      private

      def eligible?
        @subscription.is_a?(DymondBank::Subscription) &&
          @subscription.persisted? &&
          %w[active trialing].include?(@subscription.status.to_s) &&
          @subscription.subscriber&.persisted?
      end

      def same_tenant?(site)
        site.tenant_type == @subscription.subscriber.class.base_class.name &&
          site.tenant_id == @subscription.subscriber.id
      end
    end
  end
end
