module LightekPwa
  class LaunchReadiness
    IMPLEMENTATION_GAPS = {}.freeze
    def self.configuration(site)
      {
        payment_key: DymondBank::StripeCredentials.secret_key.present?,
        payment_webhook: ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].present?,
        separate_member_host: SharedPool.where(site: site, status: 'ready').any? do |pool|
          begin
            pool.isolated!
          rescue MemberBackends::Unavailable
            false
          end
        end,
        youtube_uploads_enabled: ENV['LIGHTEK_YOUTUBE_UPLOADS_ENABLED'] == 'true',
        youtube_channel_selected: ENV['LIGHTEK_YOUTUBE_CHANNEL_ID'].to_s.match?(/\AUC[A-Za-z0-9_-]{22}\z/),
        youtube_credentials_selected: ENV['LIGHTEK_YOUTUBE_CREDENTIAL_SLUG'].present?,
        creator_support_enabled: CreatorSupport.enabled?(site),
        creator_payouts_enabled: ENV['LIGHTEK_CREATOR_PAYOUTS_ENABLED'] == 'true',
        view_payouts_enabled: ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED'] == 'true',
        member_mail_enabled: ENV['LIGHTEK_MEMBER_EMAIL_ENABLED'] == 'true'
      }
    end
    def self.paid_ready?(site) = IMPLEMENTATION_GAPS.empty? && configuration(site).values.all?
    def self.report(site:)
      flags = configuration(site)
      # Configuration opens the operator's explicit sales control. It cannot
      # manufacture the real production receipts needed for a full launch.
      {launch_candidate: flags.values.all?, production_verified: false, paid_sales_ready: flags.values.all?, implementation_gaps: IMPLEMENTATION_GAPS,
        configuration: flags, production_acceptance: {
          ordinary_member: 'Fresh signup on the separate host, first post, reply, messages and mobile/install journey require deployed acceptance.',
          migration: 'Verify a shared backend upgrade on matching deployed revisions, original-media checksum, stable discovery and retained source.',
          billing: 'Successful charge, renewal/cancel, refund and creator payout require live signed receipts.',
          youtube: 'Authorize the monetized central channel and verify an actual original → upload → public embedded playback.',
          view_earnings: 'Verify a complete-channel finalized report, available platform funding and a creator transfer; a provider transfer is not bank delivery.',
          mail: 'Verify external inbound and outbound delivery, DNS and queue health.'
        }}
    end
  end
end
