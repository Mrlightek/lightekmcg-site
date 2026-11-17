module LightekPwa
  # All prices are server quotes. Checkout return URLs never establish payment.
  class CreatorSupport
    class Unavailable < StandardError; end
    def self.enabled?(site)
      Policy.platform_operator(site).present? && ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED'] == 'true'
    end
    def self.offer!(site:, creator:, monthly_cents:, enabled:)
      Policy.new(user: creator, site: site).authorize!
      raise Unavailable, 'Creator support is not open yet' unless enabled?(site)
      creator.with_lock do
        offer = CreatorOffer.find_or_initialize_by(site: site, creator: creator)
        offer.update!(monthly_cents: monthly_cents, enabled: enabled)
        offer
      end
    end
    def self.quote(site:, creator:, kind:, principal_cents:, post_id: nil)
      raise Unavailable, 'Creator support is not open yet' unless enabled?(site)
      Policy.new(user: creator, site: site).authorize!
      offer = CreatorOffer.find_by!(site: site, creator: creator, enabled: true)
      raise Unavailable, 'Choose a tip, gift or monthly subscription' unless %w[tip gift subscription].include?(kind)
      principal = kind == 'subscription' ? offer.monthly_cents : Integer(principal_cents)
      raise Unavailable, 'Choose an amount from $1 to $1,000' unless (100..100_000).cover?(principal)
      post = post_id.present? ? Post.find_by!(id: post_id, site: site, user: creator, visibility: 'public', audience: 'everyone', moderation_state: 'published', parent_id: nil) : nil
      if kind == 'gift'
        operation = post && post.kind == 'live' && StudioLiveOperation.find_by(id: post.metadata['live_operation_id'], status: 'live')
        raise Unavailable, 'Gifts are available during this creator’s live broadcast' unless operation && operation.studio_project.owner == creator && operation.studio_project.site_id == site.id && (!post.expires_at || post.expires_at.future?)
      end
      network = Integer(ENV.fetch('LIGHTEK_CREATOR_NETWORK_FEE_CENTS', '0'))
      raise Unavailable, 'Support fees need an administrator review' unless (0..500).cover?(network)
      total = LightekCommerce::MerchantPayouts.minimum_charge_cents(principal + network)
      {creator_id: creator.id, site_id: site.id, kind: kind, principal_cents: principal, fee_cents: total - principal, subtotal_cents: total, post_id: post&.id}
    rescue ArgumentError, TypeError
      raise Unavailable, 'Choose a valid whole-cent amount'
    end
    def self.checkout!(site:, supporter:, creator:, kind:, principal_cents:, post_id:, request_key:, accepted_fee_cents:, success_url:, cancel_url:)
      raise Unavailable, 'Sign in to support a creator' unless supporter
      raise Unavailable, 'You cannot pay yourself' if supporter.id == creator.id
      raise Unavailable, 'Refresh this payment and try again' unless request_key.to_s.match?(/\A[0-9a-f-]{36}\z/i)
      Policy.new(user: supporter, site: site).authorize!
      payment = nil
      supporter.with_lock do
        payment = CreatorPayment.find_by(site: site, supporter: supporter, request_key: request_key)
        if payment
          raise Unavailable, 'This payment key belongs to a different request' unless payment.creator_id == creator.id && payment.kind == kind && payment.post_id == post_id.presence&.to_i &&
            (kind == 'subscription' || payment.principal_cents == Integer(principal_cents)) && payment.fee_cents == Integer(accepted_fee_cents)
        else
          quoted = quote(site: site, creator: creator, kind: kind, principal_cents: principal_cents, post_id: post_id)
          raise Unavailable, 'The fee changed. Review the current quote before paying.' unless Integer(accepted_fee_cents) == quoted[:fee_cents]
          if kind == 'subscription'
            existing = CreatorPayment.where(site: site, supporter: supporter, creator: creator, kind: kind).includes(order: :commerce_subscription)
            raise Unavailable, 'Manage your existing creator subscription before buying another' if existing.any? { |p| p.active_subscription? || p.order.status == 'pending_payment' || p.order.commerce_subscription&.status.in?(%w[active past_due incomplete unpaid]) }
          end
          interval = kind == 'subscription' ? 'month' : 'one_time'
          slug = "creator-#{creator.id}-#{kind}-#{quoted[:principal_cents]}-#{quoted[:fee_cents]}"
          # Not a discoverable storefront product; checkout owns its immutable snapshot.
          product = LightekCommerce::Product.find_or_create_by!(site: site, slug: slug) do |p|
            p.assign_attributes(name: "#{kind == 'subscription' ? 'Monthly creator support' : kind.titleize} (creator receives $#{format('%.2f', quoted[:principal_cents] / 100.0)}; support fees included)",
              currency: 'usd', product_type: 'service', billing_interval: interval, price_cents: quoted[:subtotal_cents], published: false, track_inventory: false)
          end
          order = LightekCommerce::Order.create!(site: site, customer_email: supporter.email_address, currency: 'usd', purpose: 'creator_support', revenue_share_snapshot: [],
            status: 'pending_payment', subtotal_cents: quoted[:subtotal_cents], total_cents: quoted[:subtotal_cents], stock_reserved: false)
          order.items.create!(product: product, name: product.name, quantity: 1, unit_price_cents: quoted[:subtotal_cents], line_total_cents: quoted[:subtotal_cents],
            purchase_snapshot: {'billing_interval' => interval, 'track_inventory' => false, 'creator_support' => quoted.stringify_keys})
          payment = CreatorPayment.create!(site: site, creator: creator, supporter: supporter, order: order, request_key: request_key,
            kind: kind, post_id: quoted[:post_id], principal_cents: quoted[:principal_cents], fee_cents: quoted[:fee_cents])
          LightekCommerce::ReservationExpiryJob.set(wait: 30.minutes).perform_later(order.id)
        end
      end
      LightekCommerce::StripeCheckout.start!(order: payment.order, success_url: success_url, cancel_url: cancel_url)
    end
    def self.record!(order:, original_order: order)
      payment = CreatorPayment.find_by(order: original_order)
      return unless payment
      existing = CreatorEarning.find_by(order: order)
      return existing if existing
      raise Unavailable, 'Creator payment has not been verified' unless order.paid_at? && %w[paid fulfilled].include?(order.status) && order.subtotal_cents == payment.principal_cents + payment.fee_cents
      CreatorEarning.find_or_create_by!(order: order) do |earning|
        earning.creator_payment = payment
        earning.principal_cents = payment.principal_cents
        earning.hold_reason = 'Awaiting confirmed payment funds'
      end
    end
  end
end
