module LightekGrowth
  # Authored work blocks over reviewed business facts, not invented research.
  module MarketingPlaybook
    VERSION = 'marketing-copilot-v1'.freeze
    DAYS = [
      ['Make the offer clear', ['Review one offer, one audience and one customer problem.', 'Edit the campaign variations and choose the strongest accurate message.', 'Open the tracked destination and check how a customer can inquire or buy.']],
      ['Put one message in front of people', ['Review and approve the exact campaign copy.', 'Use the publishing workspace or share the reviewed copy with its tracked link.', 'Check actual publication or delivery receipts before recording it as sent.']],
      ['Follow up on existing interest', ['Read the saved lead context and follow-up drafts.', 'Contact appropriate existing leads through an authorized channel.', 'Record the actual conversation and next step in Sales.']],
      ['Show the offer in action', ['Open this campaign in Studio and outline a short demonstration.', 'Review the export and attach it through the publishing workflow.', 'Reuse the tracked placement link when sharing the reviewed version.']],
      ['Answer a real question', ['Read actual questions from inquiries and sales conversations.', 'Edit a campaign variation to answer one question using confirmed facts.', 'Review the exact version before sharing it.']],
      ['Check the funnel', ['Inspect tracked visits, inquiries and confirmed payments in Growth.', 'Keep unknown-source activity separate from attributed results.', 'Review due sales tasks before producing more promotional material.']],
      ['Decide what to repeat', ['Compare recorded outcomes with the saved business goal.', 'Review a measured comparison if two approved versions have placements.', 'Update the brief from what you actually learned, then prepare the next kit.']]
    ].freeze
    module_function
    def calendar(minutes)
      DAYS.each_with_index.map do |(title, steps), day|
        row = {'day_index'=>day, 'title'=>title, 'steps'=>steps.map { |text| {'text'=>text, 'minutes'=>minutes / 3} }}
        raise ArgumentError, 'The combined daily work blocks exceed the time budget' if row['steps'].sum { |step| step['minutes'] } > minutes
        row
      end
    end
    def lead_snapshot(lead, brief)
      {'lead_id'=>lead.id, 'revision'=>lead.lock_version, 'name'=>lead.name, 'company'=>lead.company,
        'status'=>lead.status, 'next_step'=>lead.next_step, 'follow_up_on'=>lead.follow_up_on&.iso8601,
        'opening'=>"Hi #{lead.name}, I’m reaching out about #{brief.offering}. For #{brief.audience}, the focus is: #{brief.value_proposition}. Would a short conversation help you decide whether it fits?",
        'next_step_draft'=>"Hi #{lead.name}, checking whether #{brief.offering} is relevant for you. #{lead.next_step.present? ? "The next step recorded in our notes is: #{lead.next_step}." : 'What would you need to know before deciding on a next step?'} Is that still useful for you?"}
    end
  end
end
