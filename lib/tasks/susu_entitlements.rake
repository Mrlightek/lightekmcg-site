namespace :susu do
  task backfill_entitlements: :environment do
    ids = SusuGroup.distinct.pluck(:organizer_id) + SusuMembership.distinct.pluck(:user_id)
    users = User.where(id: ids.compact.uniq)
    users.find_each { |user| user.grant_feature!(:susu, source: "susu_backfill") }
    puts "Granted Susu entitlement to #{users.count} existing user(s)."
  end

  task payout_readiness: :environment do
    puts "=== SUSU PAYOUT READINESS ==="
    stripe_mode =
      begin
        DymondBank::StripeCredentials.secret_key.to_s.start_with?("sk_live_") ? "live" : "test/non-live"
      rescue StandardError => e
        "unavailable (#{e.class})"
      end

    puts "Stripe mode:         #{stripe_mode}"
    puts "Entitlements table:  #{ActiveRecord::Base.connection.table_exists?("user_feature_entitlements")}"
    puts "Funded rounds:       #{SusuRound.where(status: "funded").count}"
    puts "Processing rounds:   #{SusuRound.where(status: "processing").count}"
  end
end
