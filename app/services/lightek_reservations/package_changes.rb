module LightekReservations
  module PackageChanges
    class Invalid < StandardError; end
    module_function
    # Credit only the unused value of the contracted price, never today's retail
    # price of the original plan. Integer ceiling avoids fractional-cent losses.
    def quote!(reservation:, target:, now: Time.current)
      raise Invalid, 'Only active paid server reservations can change packages' unless reservation.server? && reservation.paid? && %w[confirmed expired].include?(reservation.status) && now >= reservation.starts_at
      raise Invalid, 'Choose another server package from the same provider' unless target.server? && target.published? && target.site_id == reservation.resource.site_id
      raise Invalid, target.errors.full_messages.to_sentence unless target.valid?
      original = reservation.package_snapshot
      raise Invalid, 'Billing interval changes take effect on a new reservation' unless target.billing_interval == original['billing_interval']
      raise Invalid, 'A package change cannot change the server region or operating image' unless %w[region image].all? { |key| original.fetch('compute', {})[key] == target.compute[key] }
      difference = target.price_cents - original.fetch('price_cents')
      remaining = [(reservation.ends_at - now).to_i, 0].max
      duration = (reservation.ends_at - reservation.starts_at).to_i
      prorated = difference.positive? ? (difference * remaining + duration - 1) / duration : 0
      renewal = difference <= 0 || now >= reservation.ends_at || prorated < 50
      due = renewal ? target.price_cents : prorated
      Change.create!(reservation: reservation, target_resource: target, amount_cents: due,
        effective_at: renewal ? [reservation.ends_at, now].max : now, expires_at: 30.minutes.from_now,
        quote: {'original' => original, 'target' => target.snapshot, 'proration_at' => now.iso8601,
          'unused_seconds' => remaining, 'term_seconds' => duration, 'due_cents' => due,
          'renewal_price_cents' => target.price_cents, 'renewal' => renewal})
    end
    def accept!(change:, actor:)
      reservation = change.reservation
      reservation.with_lock do
        change.lock!
        raise Invalid, 'This reservation is not yours' unless reservation.customer_id == actor.id
        return change if %w[awaiting_payment scheduled applying applied].include?(change.status)
        raise Invalid, 'Quote expired; request a fresh price' unless change.status == 'quoted' && change.expires_at > Time.current
        raise Invalid, 'The reservation has changed; request a fresh quote' unless reservation.package_snapshot == change.quote['original'] && %w[confirmed expired].include?(reservation.status)
        raise Invalid, 'Another package change is in progress' if reservation.package_changes.where.not(id: change.id).where(status: %w[awaiting_payment scheduled applying failed]).exists?
        order = LightekCommerce::Order.create!(site: reservation.resource.site, customer_email: actor.email_address,
            purpose: 'reservation_change', stock_reserved: false, subtotal_cents: change.amount_cents, total_cents: change.amount_cents)
        order.items.create!(product: change.target_resource.product, name: "#{change.quote['renewal'] ? 'Package renewal' : 'Package upgrade'} · #{change.target_resource.name}", quantity: 1,
            unit_price_cents: change.amount_cents, line_total_cents: change.amount_cents)
        change.update!(order: order, status: 'awaiting_payment')
        LightekCommerce::ReservationExpiryJob.set(wait: 36.minutes).perform_later(order.id)
        change
      end
    end
  end
end
