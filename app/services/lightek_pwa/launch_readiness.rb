module LightekPwa
  # An operator checkbox cannot establish a missing implementation or an
  # end-to-end acceptance receipt. Keep these gaps visible until they are closed.
  class LaunchReadiness
    IMPLEMENTATION_GAPS = {
      free_member_allocation: 'Automatic, capacity-bounded free member backend allocation is not connected.',
      member_migration: 'Verified Free → Paid content/media migration, stable routing cutover and rollback are not implemented.',
      youtube_cash_settlement: 'Finalized channel revenue reconciliation and a funded creator view-earnings payout rail are not implemented.'
    }.freeze
    def self.paid_ready?(_site) = IMPLEMENTATION_GAPS.empty?
    def self.report(site:)
      flags = {
        payment_key: DymondBank::StripeCredentials.secret_key.present?,
        payment_webhook: ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].present?,
        youtube_uploads_enabled: ENV['LIGHTEK_YOUTUBE_UPLOADS_ENABLED'] == 'true',
        youtube_channel_selected: ENV['LIGHTEK_YOUTUBE_CHANNEL_ID'].to_s.match?(/\AUC[A-Za-z0-9_-]{22}\z/),
        youtube_credentials_selected: ENV['LIGHTEK_YOUTUBE_CREDENTIAL_SLUG'].present?,
        creator_support_enabled: CreatorSupport.enabled?(site),
        creator_payouts_enabled: ENV['LIGHTEK_CREATOR_PAYOUTS_ENABLED'] == 'true',
        member_mail_enabled: ENV['LIGHTEK_MEMBER_EMAIL_ENABLED'] == 'true'
      }
      {launch_candidate: false, paid_sales_ready: paid_ready?(site), implementation_gaps: IMPLEMENTATION_GAPS,
        configuration: flags, production_acceptance: {
          ordinary_member: 'Fresh signup, first post, reply, messages and mobile/install journey require deployed acceptance.',
          billing: 'Successful charge, renewal/cancel, refund and creator payout require live signed receipts.',
          youtube: 'Authorize the central channel and verify an actual original → upload → public embedded playback.',
          mail: 'Verify external inbound and outbound delivery, DNS and queue health.'
        }}
    end
  end
end
