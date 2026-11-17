module LightekPwa
  class LaunchReadiness
    IMPLEMENTATION_GAPS = {}.freeze
    def self.configuration(site)
      {
        payment_key: DymondBank::StripeCredentials.secret_key.present?,
        payment_webhook: LightekCommerce::WebhookCredentials.configured?,
        separate_member_host: SharedPool.where(site: site, status: 'ready').any? do |pool|
          begin
            pool.isolated!
          rescue MemberBackends::Unavailable
            false
          end
        end,
        youtube_uploads_enabled: LaunchSettings.enabled?('youtube_uploads_enabled'),
        youtube_channel_selected: LaunchSettings.value('youtube_channel_id').to_s.match?(/\AUC[A-Za-z0-9_-]{22}\z/),
        youtube_credentials_selected: LaunchSettings.value('youtube_credential_slug').present?,
        creator_support_enabled: CreatorSupport.enabled?(site),
        creator_payouts_enabled: LaunchSettings.enabled?('creator_payouts_enabled'),
        view_payouts_enabled: LaunchSettings.enabled?('view_payouts_enabled'),
        member_mail_enabled: LaunchSettings.enabled?('member_mail_enabled')
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
