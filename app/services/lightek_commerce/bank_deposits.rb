# frozen_string_literal: true

module LightekCommerce
  # Stripe reports which connected-account balance entries an automatic payout
  # contains. A merchant transfer is an order match only with a provider link.
  class BankDeposits
    class Unavailable < StandardError; end

    def initialize(site:, actor:)
      @site = site
      raise ActiveRecord::RecordNotFound unless site.tenant == actor &&
        LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: site.id)

      account = actor.stripe_connect_account_id.to_s
      if !account.start_with?('acct_') || LightekReservations::Federation::Client.config(site).present?
        raise Unavailable, 'Connect a local payout account to view its bank deposits here.'
      end

      platform_options = LightekPayments::PayoutAccounts.options
      connected = ::Stripe::Account.retrieve(account, platform_options)
      owner = connected.metadata.to_h.stringify_keys['lightek_user_id']
      unless connected.id == account && (owner.blank? || owner == actor.id.to_s)
        raise Unavailable, 'This bank deposit account needs verification.'
      end

      @options = platform_options.merge(stripe_account: account)
    rescue LightekPayments::PayoutAccounts::Unavailable, ::Stripe::StripeError
      raise Unavailable, 'Bank deposits are unavailable while the payout connection is being verified.'
    end

    def list(after: nil, from: nil, through: nil)
      dates = if from || through
        unless from && through && from <= through
          raise Unavailable, 'Choose a valid start and end date.'
        end
        {arrival_date: {gte: from.to_time(:utc).to_i, lt: (through + 1).to_time(:utc).to_i}}
      else
        {}
      end
      ::Stripe::Payout.list({limit: 25}.merge(dates).merge(cursor(after, 'po_')), @options)
    rescue ::Stripe::StripeError
      raise Unavailable, 'Bank deposit history is temporarily unavailable.'
    end

    def detail(id:, after: nil)
      raise ActiveRecord::RecordNotFound unless identifier?(id, 'po_')

      payout = ::Stripe::Payout.retrieve(id, @options)
      raise Unavailable, 'The provider returned a different bank deposit.' unless payout.id == id
      transactions(payout, after: after)
    rescue ::Stripe::StripeError
      raise Unavailable, 'The bank deposit or its transaction details could not be verified.'
    end

    def each_payout(from:, through:)
      after = nil
      loop do
        page = list(after: after, from: from, through: through)
        page.data.each { |payout| yield payout }
        break unless page.has_more

        after = page.data.last&.id || raise(Unavailable, 'Stripe returned an incomplete payout page.')
      end
    end

    def each_transaction(payout)
      after = nil
      loop do
        page = transactions(payout, after: after)
        page.fetch(:rows).each { |row| yield row }
        after = page[:cursor]
        break unless after
      end
    end

    private

    def transactions(payout, after:)
      if !payout.automatic || (payout.reconciliation_status.present? && payout.reconciliation_status != 'completed')
        return {payout: payout, rows: [], cursor: nil}
      end

      entries = ::Stripe::BalanceTransaction.list({payout: payout.id, limit: 100,
        expand: ['data.source']}.merge(cursor(after, 'txn_')), @options)
      data = entries.data.map { |entry| entry.to_h.deep_stringify_keys }
      references = data.filter_map { |entry| transfer_reference(entry) }.uniq
      orders = Order.visible.where(site: @site, merchant_transfer_ref: references).index_by(&:merchant_transfer_ref)
      rows = data.map do |entry|
        order = orders[transfer_reference(entry)]
        {id: entry['id'], category: entry['reporting_category'].presence || entry['type'],
         gross_cents: entry['amount'], fee_cents: entry['fee'], net_cents: entry['net'],
         currency: entry['currency'], order: order}
      end
      next_page = if entries.has_more
        data.last&.fetch('id') || raise(Unavailable, 'Stripe returned an incomplete transaction page.')
      end
      {payout: payout, rows: rows, cursor: next_page}
    rescue ::Stripe::StripeError
      raise Unavailable, 'The bank deposit or its transaction details could not be verified.'
    end

    def transfer_reference(entry)
      source = entry['source']
      return unless source.is_a?(Hash)

      value = source['source_transfer'] || source['transfer']
      value = value['id'] if value.is_a?(Hash)
      value = source['id'] if source['object'] == 'transfer'
      value if identifier?(value, 'tr_')
    end

    def cursor(value, prefix)
      return {} if value.blank?
      raise ActiveRecord::RecordNotFound unless identifier?(value, prefix)

      {starting_after: value}
    end

    def identifier?(value, prefix)
      value.to_s.match?(/\A#{Regexp.escape(prefix)}[A-Za-z0-9_]{1,150}\z/)
    end
  end
end
