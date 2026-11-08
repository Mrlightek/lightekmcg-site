# frozen_string_literal: true
require 'securerandom'
module LightekReservations
  module Booking
    class Invalid < StandardError; end
    module_function
    def reserve!(customer:, resource:, starts_at:, checkout_key:, quantity: 1, notes: nil)
      raise Invalid, 'Invalid checkout key' unless checkout_key.to_s.match?(/\A[0-9a-f-]{36}\z/i)
      quantity = Integer(quantity)
      resource.with_lock do
        existing = Reservation.find_by(customer: customer, checkout_key: checkout_key)
        if existing
          raise Invalid, 'Checkout belongs to another experience' unless existing.resource_id == resource.id
          return existing
        end
        resource.product&.lock!
        resource.valid? || raise(Invalid, resource.errors.full_messages.to_sentence)
        start = Availability.parse(starts_at, resource)
        finish = resource.server? ? (resource.billing_interval == 'annual' ? start + 1.year : start + 1.month) : start + resource.duration_minutes.minutes
        raise Invalid, 'Server packages are reserved individually' if resource.server? && quantity != 1
        Availability.check!(resource: resource, starts_at: start, ends_at: finish, quantity: quantity)
        order = if resource.product && resource.price_cents.positive?
          if resource.server?
            LightekCommerce::InstallationCheckout.reserve!(actor: customer, product: resource.product, checkout_key: checkout_key)
          else
            LightekCommerce::OrderPlacement.call(site: resource.site, customer_email: customer.email_address, quantities: {resource.product_id.to_s => quantity})
          end
        end
        reservation = Reservation.create!(resource: resource, customer: customer, order: order,
          reference: "LR-#{SecureRandom.hex(6).upcase}", checkout_key: checkout_key, starts_at: start, ends_at: finish,
          blocks_from: start - resource.buffer_minutes.minutes, blocks_until: finish + resource.buffer_minutes.minutes,
          quantity: quantity, notes: notes, package_snapshot: resource.snapshot,
          status: order ? 'held' : 'confirmed', hold_until: order ? 35.minutes.from_now : nil)
        SweepJob.set(wait: 36.minutes).perform_later if order
        reservation
      end
    rescue ArgumentError, TypeError
      raise Invalid, 'Enter a valid party size'
    end
    def reconcile!(reservation)
      reservation.with_lock do
        order = reservation.order&.reload
        return reservation unless order
        if order.paid_at? && %w[paid fulfilled].include?(order.status)
          if %w[expired canceled].include?(reservation.status)
            reservation.update!(status: 'payment_review')
          elsif reservation.status == 'held'
            reservation.update!(status: 'confirmed', hold_until: nil)
          end
        elsif order.status == 'canceled' && reservation.status == 'held'
          reservation.update!(status: 'expired')
        elsif %w[refunded partially_refunded].include?(order.status) && reservation.status == 'held'
          reservation.update!(status: 'payment_review')
        end
        reservation
      end
    end
    def cancel!(reservation:, actor:)
      # Paid cancellations retain their order and refund independently through
      # the existing refund workflow. No cancellation silently refunds money.
      reservation.with_lock do
        owner = reservation.customer_id == actor.id
        operator = LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: reservation.resource.site_id)
        raise Invalid, 'Reservation is not yours' unless owner || operator
        return reservation if %w[canceled expired].include?(reservation.status)
        raise Invalid, 'Server cancellations require an operator to review billing and retained data' if reservation.server? && !operator
        raise Invalid, 'Contact the provider: the cancellation window has closed' if !operator && reservation.starts_at < Time.current + reservation.package_snapshot.fetch('cancellation_hours', 24).hours
        raise Invalid, 'Checkout is still settling; try again after confirmation' if reservation.order&.status == 'pending_payment'
        reservation.update!(status: 'canceled', canceled_at: Time.current)
      end
      reservation
    end
    def reschedule!(reservation:, actor:, starts_at:)
      resource = reservation.resource
      resource.with_lock do
        reservation.with_lock do
          raise Invalid, 'Only confirmed appointments can be rescheduled' unless reservation.status == 'confirmed' && !reservation.server?
          raise Invalid, 'Reservation is not yours' unless reservation.customer_id == actor.id || LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: resource.site_id)
          raise Invalid, 'Contact the provider: the rescheduling window has closed' if reservation.starts_at < Time.current + reservation.package_snapshot.fetch('cancellation_hours', 24).hours
          start = Availability.parse(starts_at, resource)
          finish = start + (reservation.ends_at - reservation.starts_at)
          Availability.check!(resource: resource, starts_at: start, ends_at: finish, quantity: reservation.quantity, excluding: reservation)
          reservation.update!(starts_at: start, ends_at: finish, blocks_from: start - resource.buffer_minutes.minutes, blocks_until: finish + resource.buffer_minutes.minutes)
        end
      end
      reservation
    end
  end
end
