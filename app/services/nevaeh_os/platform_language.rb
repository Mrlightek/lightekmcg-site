# frozen_string_literal: true

require 'json'

module NevaehOs
  module PlatformLanguage
    SITE = /(?:on|for) site #?(?<site_id>[1-9]\d{0,17})/
    VERSION = /(?:at |using )?version (?<lock_version>\d{1,10})/
    QUOTED = /"(?:[^"\\\x00-\x1f]|\\.)*"/
    TIMESTAMP = /\d{4}-\d{2}-\d{2}t\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:z|[+-]\d{2}:\d{2})?/i
    SALES_TASK = /(?:sales |follow-up )?task #?(?<task_id>[1-9]\d{0,17})/i
    QUOTE_ITEM = /([1-9]\d{0,2}) of (?:product |item )?#?([1-9]\d{0,17})/i
    PHRASES = {
      'executive.case.create' => [
        /track (?<case_kind>follow_up|call|travel|expense|contract|screening) (?<title>#{QUOTED}) for my CEO Desk by (?<due_at>#{TIMESTAMP})/i,
        'Track travel "Atlanta production meetings" for my CEO Desk by 2026-11-30T14:00'
      ],
      'executive.agenda.create' => [
        /add (?:a )?(?<category>meeting|personal|travel|screening|follow_up) (?:called|named) (?<title>#{QUOTED}) to my CEO agenda from (?<starts_at>#{TIMESTAMP}) to (?<ends_at>#{TIMESTAMP})/i,
        'Add a meeting called "Launch review" to my CEO agenda from 2026-11-30T14:00 to 2026-11-30T14:30'
      ],
      'accounting.workspace.open' => [
        /open (?:the )?(?:books|accounting|books and accounting) for employer #?(?<employer_id>[1-9]\d{0,17})/i,
        'Open accounting for employer #42'
      ],
      'sessions.room.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:production |session )?room #?(?<room_id>[1-9]\d{0,17})/i,
        'Check production room #42'
      ],
      'sessions.room.invite' => [
        /invite (?<email_address>#{QUOTED}) to (?:production |session )?room #?(?<room_id>[1-9]\d{0,17})/i,
        'Invite "guest@example.com" to room #42'
      ],
      'hosting.server.list' => [
        /(?:show|list) (?:me )?my servers/i,
        'Show my servers'
      ],
      'hosting.server.status' => [
        /(?:show|check) (?:the )?(?:status of )?server #?(?<node_id>[1-9]\d{0,17})/i,
        'Check server #3'
      ],
      'hosting.fleet.rollout.list' => [
        /(?:show|list) (?:me )?(?:the )?fleet rollouts/i,
        'List fleet rollouts'
      ],
      'hosting.fleet.rollout.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:fleet )?rollout #?(?<rollout_id>[1-9]\d{0,17})/i,
        'Check fleet rollout #42'
      ],
      'hosting.fleet.rollout.control' => [
        /confirm (?<operation>start|pause|resume|retry|cancel) (?:fleet )?rollout #?(?<rollout_id>[1-9]\d{0,17})/i,
        'Confirm pause fleet rollout #42'
      ],
      'mail.mailbox.list' => [
        /(?:show|list) (?:me )?my mailboxes/i,
        'Show my mailboxes'
      ],
      'mail.mailbox.status' => [
        /(?:show|check) (?:the )?(?:status of )?mailbox #?(?<mailbox_id>[1-9]\d{0,17})/i,
        'Check mailbox #3'
      ],
      'mail.message.search' => [
        /search (?:the )?(?<folder>inbox|unread|junk|starred|sent|draft|outbox|archived|all|trash) in mailbox #?(?<mailbox_id>[1-9]\d{0,17}) for (?<query>#{QUOTED})/i,
        'Search inbox in mailbox #3 for "Proposal"'
      ],
      'mail.message.open' => [
        /open (?:mail )?message #?(?<message_id>[1-9]\d{0,17}) in mailbox #?(?<mailbox_id>[1-9]\d{0,17})/i,
        'Open message #42 in mailbox #3'
      ],
      'mail.message.flag' => [
        /set (?:mail )?message #?(?<message_id>[1-9]\d{0,17}) in mailbox #?(?<mailbox_id>[1-9]\d{0,17}) (?<flag>archived|trashed|starred|unread|junk) to (?<value>true|false)/i,
        'Set message #42 in mailbox #3 starred to true'
      ],
      'mail.draft.create' => [
        /draft (?:an )?email from mailbox #?(?<mailbox_id>[1-9]\d{0,17}) to (?<to>#{QUOTED}) with subject (?<subject>#{QUOTED}) and body (?<text>#{QUOTED})/i,
        'Draft an email from mailbox #3 to "buyer@example.com" with subject "Proposal" and body "The proposal is ready."'
      ],
      'mail.draft.send' => [
        /confirm sending (?:email )?draft #?(?<message_id>[1-9]\d{0,17}) from mailbox #?(?<mailbox_id>[1-9]\d{0,17})/i,
        'Confirm sending draft #42 from mailbox #3'
      ],
      'reservations.list' => [
        /(?:show|list) (?:me )?my reservations/i,
        'Show my reservations'
      ],
      'reservations.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:my )?reservation #?(?<reservation_id>[1-9]\d{0,17})/i,
        'Check reservation #42'
      ],
      'reservations.cancel' => [
        /cancel (?:my )?reservation #?(?<reservation_id>[1-9]\d{0,17})/i,
        'Cancel my reservation #42'
      ],
      'reservations.reschedule' => [
        /reschedule (?:my )?reservation #?(?<reservation_id>[1-9]\d{0,17}) to (?<starts_at>#{TIMESTAMP})/i,
        'Reschedule my reservation #42 to 2027-03-31T15:30:00-04:00'
      ],
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
      'sales.quote.draft' => [
        /draft (?:a )?quote for (?:deal|opportunity) #?(?<opportunity_id>[1-9]\d{0,17}) #{SITE} (?:called|named) (?<title>#{QUOTED}) for (?<customer_email>#{QUOTED}) expiring (?<expires_on>\d{4}-\d{2}-\d{2}) with (?<quantities>#{QUOTE_ITEM}(?: and #{QUOTE_ITEM})*)/i,
        'Draft a quote for deal #42 on site #3 called "Spring launch" for "buyer@example.com" expiring 2027-03-31 with 2 of product #7'
      ],
      'sales.quote.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:sales )?quote #?(?<quote_id>[1-9]\d{0,17}) #{SITE}/i,
        'Show quote #42 on site #3'
      ],
      'sales.quote.accept' => [
        /record customer approval for (?:sales )?quote #?(?<quote_id>[1-9]\d{0,17}) #{SITE} from (?<accepted_name>#{QUOTED}) with reference (?<acceptance_reference>#{QUOTED})/i,
        'Record customer approval for quote #42 on site #3 from "Jane Doe" with reference "Approval email"'
      ],
      'sales.task.status' => [
        /(?:show|check) (?:the )?(?:status of )?#{SALES_TASK} #{SITE}/i,
        'Check sales task #42 on site #3'
      ],
      'sales.task.schedule' => [
        /schedule (?:a )?(?:sales (?:task|follow-up)|follow-up) (?:called|named) (?<title>#{QUOTED}) for (?<record_kind>lead|account|contact|opportunity|prospect) #?(?<record_id>[1-9]\d{0,17}) #{SITE} assigning (?:it to )?(?:user )?#?(?<owner_id>[1-9]\d{0,17}) due (?<due_at>#{TIMESTAMP})/i,
        'Schedule a follow-up called "Send proposal" for lead #42 on site #3 assigning user #5 due 2027-03-31T15:30:00-04:00'
      ],
      'sales.task.complete' => [
        /complete #{SALES_TASK} #{SITE} #{VERSION}/i,
        'Complete sales task #42 on site #3 at version 0'
      ],
      'sales.task.cancel' => [
        /cancel #{SALES_TASK} #{SITE} #{VERSION}/i,
        'Cancel sales task #42 on site #3 at version 0'
      ],
      'sales.task.snooze' => [
        /snooze #{SALES_TASK} #{SITE} #{VERSION} until (?<due_at>#{TIMESTAMP})/i,
        'Snooze sales task #42 on site #3 at version 0 until 2027-03-31T15:30:00-04:00'
      ],
      'marketing.publication.status' => [
        /(?:show|check) (?:the )?(?:status of )?(?:publication|publishing) slot #?(?<slot_id>[1-9]\d{0,17}) #{SITE}/i,
        'Check publication slot #12 on site #3'
      ],
      'marketing.publication.cancel' => [
        /cancel (?:publication|publishing) slot #?(?<slot_id>[1-9]\d{0,17}) #{SITE} #{VERSION}/i,
        'Cancel publication slot #12 on site #3 at version 0'
      ],
      'website.design.list' => [
        /(?:show|list) (?:me )?my website designs/i,
        'Show my website designs'
      ],
      'website.design.create' => [
        /create (?:a )?website design (?:called|named) (?<name>#{QUOTED})/i,
        'Create a website design called "Spring launch"'
      ],
      'website.design.status' => [
        /(?:show|check) (?:my )?website design #?(?<design_id>[1-9]\d{0,17})/i,
        'Check website design #42'
      ],
      'website.design.publish' => [
        /publish (?:my )?website design #?(?<design_id>[1-9]\d{0,17}) to the library (?:at |using )?revision (?<revision>\d{1,10})/i,
        'Publish website design #42 to the library at revision 1'
      ],
      'website.theme.activate' => [
        /activate (?:website )?theme #?(?<template_id>[1-9]\d{0,17}) #{SITE}/i,
        'Activate website theme #42 on site #3'
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
        payload['confirmed'] = true if %w[sales.quote.accept mail.draft.send hosting.fleet.rollout.control].include?(intent)
        payload['currency']&.upcase!
        payload['folder']&.downcase!
        payload['case_kind']&.downcase!
        payload['category']&.downcase! if intent == 'executive.agenda.create'
        payload['operation']&.downcase!
        if intent == 'mail.message.flag'
          payload['flag'].downcase!
          payload['value'] = payload.fetch('value').casecmp?('true')
        end
        payload['record_kind']&.downcase!
        if payload.key?('quantities')
          items = payload.fetch('quantities').scan(QUOTE_ITEM)
          quantities = items.to_h { |quantity, id| [id, Integer(quantity, 10)] }
          raise ArgumentError, 'Include each quote product once' unless quantities.size == items.size

          payload['quantities'] = quantities
        end
        return {'kind'=>'capability', 'intent'=>intent, 'payload'=>payload}
      end
      nil
    end
  end
end
