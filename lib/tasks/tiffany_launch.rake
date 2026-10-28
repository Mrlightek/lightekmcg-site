# frozen_string_literal: true
namespace :lightek do
  namespace :launch do
    desc "Inspect real merchant readiness without creating charges or cloud resources"
    task tiffany: :environment do
      puts "LIGHTEK TIFFANY LAUNCH READINESS"
      checks = {
        "Stripe secret configured" => DymondBank::StripeCredentials.secret_key.present?,
        "Stripe webhook signing secret configured" => ENV.fetch("LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET", "").present?,
        "Physical shipping rates configured" => ENV.fetch("LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS", "").present?,
        "Active Storage service" => ActiveStorage::Blob.service.present?,
        "Published products present" => LightekCommerce::Product.where(published: true).exists?,
        "Existing store sites" => DymondSite::Site.exists?
      }
      checks.each { |name, ok| puts "#{ok ? 'OK' : 'CHECK'}: #{name}" }
      puts "Shipping rates apply only to physical products."
      puts "This command checks configuration, not provider acceptance or cloud deployment."
    end
  end
end
