# frozen_string_literal: true

require 'json'

module NevaehOs
  module PlatformLanguage
    SITE = /(?:on|for) site #?(?<site_id>[1-9]\d{0,17})/
    VERSION = /(?:at |using )?version (?<lock_version>\d{1,10})/
    QUOTED = /"(?:[^"\\\x00-\x1f]|\\.)*"/
    PHRASES = {
      'commerce.order.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:commerce )?order #?(?<order_id>[1-9]\d{0,17}) #{SITE}/i,
        'Check order #42 on site #3'
      ],
      'commerce.order.fulfill' => [
        /fulfill (?:commerce )?order #?(?<order_id>[1-9]\d{0,17}) #{SITE} with reference (?<reference>#{QUOTED})/i,
        'Fulfill order #42 on site #3 with reference "Delivery receipt"'
      ],
      'commerce.order.provisioning.retry' => [
        /retry (?:the )?installation for (?:commerce )?order #?(?<order_id>[1-9]\d{0,17}) #{SITE}/i,
        'Retry installation for order #42 on site #3'
      ],
      'sales.lead.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:sales )?lead #?(?<lead_id>[1-9]\d{0,17}) #{SITE}/i,
        'Show lead #12 on site #3'
      ],
      'sales.lead.convert' => [
        /convert (?:sales )?lead #?(?<lead_id>[1-9]\d{0,17}) #{SITE} #{VERSION} (?:to|into) (?:a )?deal (?:called|named) (?<name>#{QUOTED}) for (?<amount>\d{1,14}(?:\.\d{1,2})?) (?<currency>[a-z]{3}) closing (?<close_on>\d{4}-\d{2}-\d{2})/i,
        'Convert lead #12 on site #3 at version 0 to a deal called "Spring launch" for 1500.00 USD closing 2027-03-31'
      ],
      'sales.quote.issue' => [
        /issue (?:sales )?quote #?(?<quote_id>[1-9]\d{0,17}) #{SITE} #{VERSION}/i,
        'Issue quote #42 on site #3 at version 0'
      ],
      'sales.quote.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:sales )?quote #?(?<quote_id>[1-9]\d{0,17}) #{SITE}/i,
        'Show quote #42 on site #3'
      ],
      'sales.quote.accept' => [
        /record customer approval for (?:sales )?quote #?(?<quote_id>[1-9]\d{0,17}) #{SITE} from (?<accepted_name>#{QUOTED}) with reference (?<acceptance_reference>#{QUOTED})/i,
        'Record customer approval for quote #42 on site #3 from "Jane Doe" with reference "Approval email"'
      ],
      'marketing.publication.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:publication|publishing) slot #?(?<slot_id>[1-9]\d{0,17}) #{SITE}/i,
        'Check publication slot #12 on site #3'
      ],
      'marketing.publication.cancel' => [
        /cancel (?:publication|publishing) slot #?(?<slot_id>[1-9]\d{0,17}) #{SITE} #{VERSION}/i,
        'Cancel publication slot #12 on site #3 at version 0'
      ]
    }.freeze

    module_function

    def command(text)
      text = text.sub(/\A(?:please |(?:can|could|would) you (?:please )?)/i, '').sub(/[.!?]\z/, '')
      PHRASES.each do |intent, (pattern, _)|
        match = /\A#{pattern}\z/.match(text)
        next unless match

        payload = match.named_captures.transform_values do |value|
          value.start_with?('"') ? JSON.parse(value) : value
        end
        payload['confirmed'] = true if intent == 'sales.quote.accept'
        payload['currency']&.upcase!
        return {'kind'=>'capability', 'intent'=>intent, 'payload'=>payload}
      end
      nil
    end
  end
end
