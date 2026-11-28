# frozen_string_literal: true

require 'csv'

module LightekCommerce
  class GiftLiability
    class Unavailable < StandardError; end

    FIELDS = {
      'issued_count' => 'Cards issued',
      'face_cents' => 'Issued value',
      'voided_cents' => 'Voided value',
      'available_cents' => 'Unspent balance',
      'held_cents' => 'Reserved at checkout',
      'redeemed_cents' => 'Captured redemptions',
      'restored_cents' => 'Restored by refunds',
      'restricted_cents' => 'Blocked or disputed balance',
      'outstanding_cents' => 'Total outstanding'
    }.freeze

    def self.for_store(site)
      reports = {'Store ledger' => summarize(GiftCard.where(site: site, store_scope: "site-#{site.id}"))}
      client = LightekReservations::Federation::Client
      if client.config(site).present?
        response = client.new(site).request('commerce/gift-liability', method: :post,
          body: {gift_store_key: GiftCards.source_store_key(site)})
        remote = response['balances'] if response.is_a?(Hash)
        reports['Platform ledger'] = %w[live test].to_h do |mode|
          data = remote[mode] if remote.is_a?(Hash)
          raise Unavailable, 'The platform returned an invalid gift-card report.' unless data.is_a?(Hash)

          [mode, FIELDS.keys.to_h { |field| [field, Integer(data.fetch(field).to_s, 10)] }]
        end
      end
      reports
    rescue LightekReservations::Federation::Client::Unavailable, KeyError, ArgumentError, TypeError
      raise Unavailable, 'The platform gift-card report is temporarily unavailable.'
    end

    def self.for_peer(peer, store_key)
      scope = GiftCards.network_scope(peer, store_key)
      summarize(GiftCard.where(store_scope: scope))
    end

    def self.summary_csv(reports, generated_at:)
      CSV.generate do |csv|
        csv << ['generated_at_utc', 'ledger', 'payment_mode', 'currency', *FIELDS.keys]
        reports.each do |ledger, balances|
          balances.each do |mode, amounts|
            csv << [generated_at.utc.iso8601, ledger, mode, 'USD', *amounts.values_at(*FIELDS.keys)]
          end
        end
      end
    end

    def self.summarize(cards)
      ledger = GiftRedemption.where(gift_card_id: cards.select(:id)).group(:gift_card_id).select(
        :gift_card_id,
        "SUM(CASE WHEN state = 'held' THEN amount_cents ELSE 0 END) AS held_cents",
        "SUM(CASE WHEN state IN ('captured', 'refunded') THEN amount_cents ELSE 0 END) AS redeemed_cents",
        "SUM(CASE WHEN state = 'refunded' THEN amount_cents ELSE 0 END) AS restored_cents"
      )
      rows = cards.joins("LEFT JOIN (#{ledger.to_sql}) AS redemption_totals ON redemption_totals.gift_card_id = lightek_commerce_gift_cards.id")
        .group(:livemode).pluck(:livemode, *[
          'COUNT(*)',
          'SUM(face_cents)',
          'SUM(CASE WHEN revoked_at IS NOT NULL THEN face_cents ELSE 0 END)',
          'SUM(CASE WHEN revoked_at IS NULL THEN available_cents ELSE 0 END)',
          'SUM(CASE WHEN revoked_at IS NULL THEN COALESCE(held_cents, 0) ELSE 0 END)',
          'SUM(COALESCE(redeemed_cents, 0))',
          'SUM(COALESCE(restored_cents, 0))',
          'SUM(CASE WHEN revoked_at IS NULL AND (blocked_at IS NOT NULL OR disputed_at IS NOT NULL) THEN available_cents + COALESCE(held_cents, 0) ELSE 0 END)'
        ].map { |expression| Arel.sql(expression) })
      balances = rows.to_h { |live, *totals| [live ? 'live' : 'test', totals.map(&:to_i)] }
      %w[live test].to_h do |mode|
        values = FIELDS.keys.zip(balances.fetch(mode, Array.new(FIELDS.size, 0))).to_h
        values['outstanding_cents'] = values.fetch('available_cents') + values.fetch('held_cents')
        [mode, values]
      end
    end
    private_class_method :summarize
  end
end
