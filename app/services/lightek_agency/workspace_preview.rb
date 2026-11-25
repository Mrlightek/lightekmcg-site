# frozen_string_literal: true

module LightekAgency
  module WorkspacePreview
    VERSION = 'workspace-collaboration'

    SCENARIOS = {
      'portfolio' => {
        project: 'Portfolio review',
        deliverable: 'Case study draft',
        next_action: 'Choose the case study cover and confirm the consultation link.',
        checkpoint: 'Case study approved for the portfolio',
        channel: 'portfolio-review',
        budget_item: 'Design and content hours',
        hours: 12,
        rate: 125
      },
      'campaign_delivery' => {
        project: 'Fundraising campaign',
        deliverable: 'Campaign brief',
        next_action: 'Confirm the audience, launch date, and reporting owner.',
        checkpoint: 'Landing page and campaign calendar approved',
        channel: 'campaign-delivery',
        budget_item: 'Strategy and production hours',
        hours: 18,
        rate: 110
      },
      'client_migration' => {
        project: 'Client website migration',
        deliverable: 'Cutover plan',
        next_action: 'Confirm redirects, form delivery, and the rollback owner.',
        checkpoint: 'Pilot site checks completed before cutover',
        channel: 'client-migration',
        budget_item: 'Migration and QA hours',
        hours: 20,
        rate: 135
      }
    }.transform_values(&:freeze).freeze

    def self.for(key)
      SCENARIOS.fetch(key.to_s, SCENARIOS.fetch('client_migration'))
    end

    def self.for_trial(business_type)
      self.for({'web_design' => 'portfolio', 'marketing' => 'campaign_delivery'}[business_type])
    end
  end
end
