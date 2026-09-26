# frozen_string_literal: true

namespace :gatekeeper do
  desc "Verify Gatekeeper/Susu DymondDash FeatureRegistry registrations"
  task dashboard_nav: :environment do
    slugs = %i[gatekeeper_infrastructure susu]
    missing = slugs.reject { |slug| DymondDash::FeatureRegistry.find(slug) }

    if missing.any?
      abort "Missing DymondDash feature registrations: #{missing.join(', ')}"
    end

    puts "DymondDash native features registered:"
    slugs.each do |slug|
      feature = DymondDash::FeatureRegistry.find(slug)
      puts "  #{feature.nav_section} -> #{feature.label}"
    end
  end
end
