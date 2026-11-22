# frozen_string_literal: true

require 'openssl'
require 'json'

module NevaehOs
  module PhoneIntake
    PURPOSE = 'executive_phone_intake'
    MAX_BYTES = 12.kilobytes
    class Denied < StandardError; end

    module_function

    def configure!(owner:, assignee:, secret:)
      raise LightekPeople::Access::Denied unless ExecutiveBrief.available_to?(owner)
      raise ArgumentError, 'Use a signing secret of 32–200 characters.' unless secret.to_s.bytesize.between?(32, 200)

      owner.with_lock do
        route = NevaehExecutivePhoneRoute.find_or_initialize_by(owner: owner)
        route.key ||= SecureRandom.hex(24)
        LightekVault::Service.store!(name: 'Executive phone intake signing secret', slug: route.secret_slug,
          purpose: PURPOSE, payload: {'signing_key'=>secret},
          access_policy: {'consumers'=>[name], 'purposes'=>[PURPOSE]}, requested_by: owner.email_address)
        route.update!(assignee: assignee)
        route
      end
    end

    def receive!(key:, timestamp:, signature:, body:)
      raise Denied unless key.to_s.match?(/\A[0-9a-f]{48}\z/) &&
        timestamp.to_s.match?(/\A[0-9]{10}\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300 &&
        signature.to_s.match?(/\A[0-9a-f]{64}\z/)
      raise ArgumentError, 'Event is too large.' if body.bytesize > MAX_BYTES

      route = NevaehExecutivePhoneRoute.find_by(key: key)
      raise Denied unless route && ExecutiveBrief.available_to?(route.owner)

      credentials = LightekVault::Service.checkout!(slug: route.secret_slug, consumer: name, purpose: PURPOSE, requested_by: 'executive-phone-webhook')
      secret = credentials.fetch('signing_key')
      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")
      raise Denied unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)

      data = JSON.parse(body)
      unless data.is_a?(Hash) && (data.keys - %w[event_id kind caller summary urgent]).empty? &&
          data['event_id'].is_a?(String) && data['event_id'].match?(/\A[a-zA-Z0-9_-]{1,90}\z/) &&
          %w[missed voicemail].include?(data['kind']) && (data['caller'].nil? || data['caller'].to_s.match?(/\A\+?[0-9]{3,20}\z/)) &&
          data['summary'].to_s.length <= 7_000 && [nil, true, false].include?(data['urgent'])
        raise ArgumentError, 'Use a valid missed-call or voicemail event.'
      end

      route.with_lock do
        event = "phone:#{data.fetch('event_id')}"
        NevaehExecutiveCase.find_or_create_by!(owner: route.owner, source_event: event) do |item|
          staff = LightekPeople::Employment.active.exists?(employer: route.owner, worker_id: route.assignee_id)
          assignee = route.assignee if staff && LightekPeople::LifecycleAccess.active?(route.assignee)
          item.assign_attributes(assignee: assignee, status: assignee ? 'in_review' : 'open', kind: 'call',
            title: data['kind'] == 'voicemail' ? 'Voicemail to review' : 'Missed call to review',
            details: ["Caller: #{data['caller'].presence || 'Withheld'}", data['summary']].compact.join("\n"),
            due_at: data['urgent'] ? Time.current : 2.hours.from_now)
        end
      end
    rescue JSON::ParserError
      raise ArgumentError, 'Use a valid JSON event.'
    rescue LightekVault::Service::AccessDenied, KeyError
      raise Denied
    ensure
      secret&.clear if secret.is_a?(String) && !secret.frozen?
    end
  end
end
