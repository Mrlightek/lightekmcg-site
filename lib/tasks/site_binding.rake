# frozen_string_literal: true
namespace :lightek do
  namespace :site_binding do
    desc "Verify the release domain maps to a real website and its PWA"
    task verify: :environment do
      site = LightekSettings::SiteDomain.verify!(host: ENV.fetch("LIGHTEK_EXPECTED_SITE_HOST"))
      puts "LIGHTEK_SITE_BINDING_OK site_id=#{site.id} host=#{site.host}"
    end
  end
end
