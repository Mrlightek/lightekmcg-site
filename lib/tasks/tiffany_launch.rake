# frozen_string_literal: true
namespace :lightek do
  namespace :launch do
    desc "Inspect Tiffany's exact Commerce deployment and payment readiness; never creates charges"
    task tiffany: :environment do
      target_id = ENV.fetch("TIFFANY_SITE_ID", "").to_s
      site = DymondSite::Site.find_by(id: target_id) if target_id.match?(/\A[1-9]\d*\z/)
      puts "LIGHTEK TIFFANY MERCHANT LAUNCH READINESS"
      puts "Site: #{site ? "#{site.id} / #{site.name}" : "NOT SELECTED - set TIFFANY_SITE_ID"}"
      checks = {
        "Tiffany site identified" => site.present?,
        "Stripe secret available via Dymond Bank" => DymondBank::StripeCredentials.secret_key.present?,
        "Commerce webhook secret" => ENV["LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET"].present?,
        "Active Storage backend" => ActiveStorage::Blob.service.present?,
        "Products exist on Tiffany site" => site && LightekCommerce::Product.where(site: site).exists?,
        "Published, in-stock products on Tiffany site" => site && LightekCommerce::Product.where(site: site, published: true).where("inventory_quantity > 0").exists?,
        "Shipping rate IDs for physical goods" => ENV["LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS"].present?
      }
      checks.each { |name, ok| puts "#{ok ? 'OK' : 'CHECK'}: #{name}" }
      puts "NOTE: shipping rates are required for physical goods, not digital-only checkouts."
      puts "VERIFY SEPARATELY: Tiffany's dedicated VPS, DNS/TLS, Stripe webhook test, an actual checkout and merchant receipt of funds."
      abort "Launch configuration incomplete" unless checks.except("Shipping rate IDs for physical goods").values.all?
    end
  end
end
