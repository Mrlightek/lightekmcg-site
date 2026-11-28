# frozen_string_literal: true

module LightekCommerce
  class GiftDelivery
    MAX_SCHEDULE_DAYS = 180

    def self.attributes(customer_email:, recipient_email:, delivery_date:)
      requested_day = delivery_date.to_s.presence
      return {} if recipient_email.blank? && !requested_day

      deliver_at = nil
      if requested_day
        day = Date.iso8601(requested_day)
        unless day.between?(Date.current, Date.current + MAX_SCHEDULE_DAYS)
          raise GiftCards::Invalid, 'Choose a gift delivery date within the next 180 days.'
        end

        deliver_at = Time.zone.local(day.year, day.month, day.day, 9)
      end
      {gift_recipient_email: email!(recipient_email.presence || customer_email), gift_deliver_at: deliver_at}
    rescue Date::Error
      raise GiftCards::Invalid, 'Choose a valid gift delivery date.'
    end

    def self.network_attributes(recipient, delivery_time)
      return {} if recipient.nil? && delivery_time.nil?

      scheduled = Time.iso8601(delivery_time) if delivery_time
      if scheduled && scheduled > MAX_SCHEDULE_DAYS.days.from_now + 1.day
        raise GiftCards::Invalid, 'Choose a gift delivery date within the next 180 days.'
      end

      {gift_recipient_email: email!(recipient), gift_deliver_at: scheduled}
    rescue ArgumentError, TypeError
      raise GiftCards::Invalid, 'Choose a valid gift delivery time.'
    end

    def self.enqueue(order)
      return unless order.gift_card_purchase? && order.managed_gift_delivery? && !order.gift_delivered_at? && order.status == 'fulfilled'

      if order.gift_deliver_at&.future?
        GiftDeliveryJob.set(wait_until: order.gift_deliver_at).perform_later(order.id)
      else
        GiftDeliveryJob.perform_later(order.id)
      end
    end

    def self.email!(value)
      email = value.to_s.strip
      unless email.size <= 254 && URI::MailTo::EMAIL_REGEXP.match?(email)
        raise GiftCards::Invalid, 'Enter a valid email address for the gift recipient.'
      end

      email
    end
    private_class_method :email!
  end
end
