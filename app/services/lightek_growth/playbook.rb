module LightekGrowth
  # Authored rules over measured facts. Neither model prose nor brief text can
  # select an executable capability or establish a causal marketing claim.
  class Playbook
    VERSION = 'growth-daily-v2'.freeze
    def self.recommendations(snapshot)
      facts = snapshot.fetch('facts')
      candidates = []
      add = lambda do |key, title, reason, destination, evidence, instructions, action = 'navigate'|
        candidates << {'key' => key, 'title' => title, 'reason' => reason, 'destination' => destination, 'evidence' => evidence, 'instructions' => instructions, 'action' => action}
      end
      unless snapshot['brief_complete']
        add.call('brief', 'Finish your business growth brief', 'Clear audience, problem, offer and goal information is needed before preparing marketing copy.', 'brief', {'missing_fields' => snapshot['missing_brief_fields']}, ['Describe the customer and their problem.', 'Explain your offer and why it helps.', 'Set a concrete business goal, then refresh this plan.'])
      end
      if facts['review_inquiries'] > 0
        add.call('inquiries', 'Review incoming customer inquiries', 'These requests have not yet been accepted or resolved. Review them before spending more effort attracting new inquiries.', 'intake', facts.slice('review_inquiries'), ['Open Inquiry inbox and review the original request.', 'Confirm the contact details and accept legitimate inquiries.', 'Use the resulting follow-up task to arrange the next conversation.'])
      end
      if facts['paid_undelivered'] > 0
        add.call('delivery', 'Check paid orders awaiting delivery', 'Recorded payment exists, but no fulfillment or provisioning completion is recorded. Protect the customer experience before expanding promotion.', 'orders', facts.slice('paid_undelivered'), ['Check the paid order and its promised delivery.', 'Complete delivery or investigate the existing provisioning job.', 'Record the actual fulfillment evidence in Commerce.'])
      end
      if facts['due_tasks'] > 0
        add.call('follow_up', 'Follow through on due sales tasks', 'Open sales tasks are due. They can represent an existing customer conversation rather than a need for more traffic.', 'tasks', facts.slice('due_tasks'), ['Review due tasks and their assigned owners.', 'Open the related lead or deal and agree on the next step.', 'Complete or reschedule the task after the actual follow-up.'])
      end
      if facts['expiring_quotes'] > 0
        add.call('quotes', 'Review quotes approaching expiry', 'Issued quotes expire within three days. Confirm the customer has what they need; an issued quote is not a payment.', 'sales', facts.slice('expiring_quotes'), ['Open the proposal or negotiation deals.', 'Check the issued quote and contact the customer through an authorized channel.', 'Revise expired commercial details rather than accepting an outdated offer.'])
      end
      if facts.key?('website_audit_id')
        if facts['website_audit_id'].nil? || facts['website_audit_stale']
          add.call('website_audit', 'Refresh your website evidence', 'A current native website audit is needed before making website optimization claims.', 'website_audit', facts.slice('website_audit_id', 'website_audit_stale'), ['Run a native website audit for the selected business.', 'Review assessed and unassessed pages.', 'Prioritize evidence-backed fixes and refresh this plan.'])
        elsif facts['website_audit_open'].to_i > 0 || facts['website_audit_unassessed'].to_i > 0 || facts['website_audit_incomplete']
          add.call('website_audit', 'Review website growth findings', 'The latest full-site native audit has open findings or unassessed pages. Review the source and evidence before changing the site.', 'website_audit', facts.slice('website_audit_id', 'website_audit_open', 'website_audit_high', 'website_audit_unassessed'), ['Open the audit and review the affected page.', 'Prepare a supported change or record why no change is needed.', 'Apply only an approved preview, then check the re-audit result.'])
        end
      end
      if snapshot['brief_complete'] && snapshot.dig('brief', 'goal_on').present? && snapshot.dig('brief', 'goal_on') <= snapshot.fetch('window_to')
        add.call('goal_review', 'Review your business goal and deadline', 'The saved goal date has arrived. Compare actual outcomes with your goal and decide the next target; this playbook does not interpret free-text goals as verified results.', 'brief', {'goal_on' => snapshot.dig('brief', 'goal_on')}, ['Review the measured funnel and actual order outcomes.', 'Record what was achieved and what still needs work.', 'Update the goal and date, then refresh the plan.'])
      end
      if snapshot['brief_complete']
        if facts['campaigns'] == 0
          add.call('first_campaign', 'Prepare your first campaign draft', 'Your business brief is ready, but this website has no campaign. Start with one clear offer and audience.', 'campaigns', facts.slice('campaigns'), ['Prepare an editable campaign from the reviewed brief.', 'Review the headline, offer and call to action.', 'Create a tracking link before sharing it.'], 'create_campaign')
        elsif facts['enabled_links'] == 0
          add.call('tracking', 'Give your campaign a tracked link', 'No campaign link is enabled, so the next promotion cannot be traced through the native funnel.', 'links', facts.slice('enabled_links', 'campaigns'), ['Choose the campaign you intend to promote.', 'Create a link for its channel and placement.', 'Test the destination and use that link when you share.'])
        elsif facts['tracked_visits'] == 0
          add.call('distribution', 'Review where your campaign link is shared', 'No tracked visits were recorded in the last seven days. This does not establish that the website had no traffic.', 'links', facts.slice('tracked_visits', 'enabled_links'), ['Test the enabled link and its destination.', 'Check that it is used on the intended profile, email or approved post.', 'Review later results; do not interpret untracked traffic as zero traffic.'])
        elsif facts['tracked_visits'] >= 20 && facts['inquiry_visits'] == 0 && facts['paid_visits'] == 0
          add.call('landing', 'Review the campaign landing experience', 'The seven-day cohort has at least 20 recorded link visits, with no attributed inquiry or payment yet. This is a review prompt, not proof of a conversion problem.', 'website', facts.slice('tracked_visits', 'inquiry_visits', 'paid_visits'), ['Check the offer, destination and contact form on a phone.', 'Confirm the form and checkout work before changing your message.', 'Make one deliberate change and compare future cohorts; previews and privacy settings can affect counts.'])
        else
          add.call('next_campaign', 'Prepare a focused campaign variation', 'The basic measurement path is in place. Use a reviewed draft to test another message while keeping the same audience and offer.', 'campaigns', facts.slice('tracked_visits', 'inquiry_visits', 'paid_visits'), ['Prepare a draft grounded in the business brief.', 'Review it and create the appropriate media in Studio.', 'Use a separate tracked placement and compare observed results.'], 'create_campaign')
        end
      end
      candidates.first(5)
    end
  end
end
