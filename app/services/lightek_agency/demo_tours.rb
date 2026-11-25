# frozen_string_literal: true

module LightekAgency
  module DemoTours
    VERSION = "website-releases"
    SHARED_STEPS = [
      ['Bring your own HTML & CSS',
        'Download the starter and upload your HTML and CSS as a draft from the browser. Lightek supplies the live menu, shared footer, product catalog, cart and checkout.',
        :dashboard_website_designs_path, {theme_kit: 1, anchor: 'html-css-theme-kit'}],
      ['Practice an agency release',
        'Select the client in the Agency Dashboard, stage a draft on the exact hostname, review the revision, publish, then restore the previous theme. Live publishing requires verified agency MFA.',
        :release_practice]
    ].freeze

    PRESETS = {
      'portfolio' => {
        label: 'Portfolio & consultations',
        intro: 'Show what you did for a client and give the next prospect a way to get in touch.',
        practice_host: 'design-client.example',
        practice_release: 'Portfolio refresh',
        steps: [
          ['Walk through the portfolio', 'Open the private showcase, filter the sample projects, and follow a project into its case study.', :preview_dashboard_agency_portfolio_path],
          ['Make a case study yours', 'In Pages & Sections, change a sample project’s cover, brief, or outcome. Return to the preview to see the edit.', :pages],
          ['Connect the consultation', 'On Selected work, edit the Portfolio Index section and add your consultation or proposal URL.', :pages]
        ]
      },
      'campaign_delivery' => {
        label: 'Discovery to campaign reporting',
        intro: 'Follow one engagement from the first conversation through the campaign and its reporting review.',
        practice_host: 'campaign-client.example',
        practice_release: 'Fundraising campaign page',
        steps: [
          ['Capture the discovery brief', 'Create a sample inquiry in Leads. Choose whether you’re supporting, leading, or acting as the client’s team. Record that scope and the next decision.', :dashboard_sales_path, {tab: 'leads'}],
          ['Turn the brief into a proposal', 'Open the sales pipeline and see where a qualified opportunity becomes a draft quote for a client to review.', :dashboard_sales_path, {tab: 'pipeline'}],
          ['Plan what the client will see', 'Open Design & Content and prepare a draft campaign landing page for the engagement.', :dashboard_website_designs_path],
          ['Review the delivery calendar', 'See where planned publications appear once approved and scheduled by a publishing operator.', :dashboard_publication_calendar_path],
          ['Open the reporting workspace', 'See where approved campaign comparisons and their evidence are reviewed once tracked traffic is available.', :dashboard_campaign_performance_path]
        ]
      },
      'client_migration' => {
        label: 'Client migration & handoff',
        intro: 'Use one representative client website to prove the handoff before planning a live move.',
        practice_host: 'service-client.example',
        practice_release: 'Service website pilot',
        steps: [
          ['Open the client workspace', 'Check that the working website is this demo. Website content and tools are scoped to the selected client site.', :dashboard_business_hub_path],
          ['Recreate a representative page', 'Use Pages & Sections to review the demo homepage and try a sample edit. Compare the result with the current site before cutover.', :pages],
          ['Check client access', 'Review the site’s team access screen. Agree who should own or edit the site before moving a real client.', :dashboard_agency_memberships_path]
        ],
        closing: 'Start the live pilot with a service website. Verify pages, URLs, form delivery, client access, reseller pricing, and rollback. Qualify stores separately for checkout and fulfillment, and custom apps for runtime, data, and integrations.'
      }
    }.freeze

    def self.options
      PRESETS.map { |key, preset| [preset.fetch(:label), key] }
    end

    def self.fetch(key)
      PRESETS[key.to_s]
    end

    def self.steps(preset)
      preset.fetch(:steps) + SHARED_STEPS
    end

    def self.prepare!(site:, key:)
      return unless key == 'portfolio'

      LightekDesign::AgencyPortfolio.install!(site)
    end
  end
end
