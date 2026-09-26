module Susu
  class PayoutService
    class NotReady < StandardError; end

    def self.request!(round:, requested_by:)
      new(round:, requested_by:).request!
    end

    def initialize(round:, requested_by:)
      @round = round
      @requested_by = requested_by
    end

    def request!
      validate!

      round.with_lock do
        return DymondBank::Payout.find(round.dymond_bank_payout_id) if round.dymond_bank_payout_id.present?

        round.refresh_collected_amount!
        raise NotReady, "Round is not fully funded" unless round.fully_funded?

        recipient = round.recipient
        DymondBank::StripeService.sync_connect_status!(recipient)
        raise NotReady, "Recipient payout account is not ready" unless recipient.stripe_connect_ready?

        payout = DymondBank::Payout.create!(
          recipient: recipient,
          status: "pending",
          currency: "usd",
          amount_cents: Money.from_amount(round.expected_pot).cents,
          fee_cents: 0,
          description: "Susu #{round.susu_group.name} round #{round.number}"
        )

        round.update!(status: "processing", dymond_bank_payout_id: payout.id)

        transfer = DymondBank::StripeService.create_transfer(
          amount_cents: payout.amount_cents,
          currency: payout.currency,
          destination_account: recipient.stripe_connect_account_id,
          description: payout.description,
          metadata: {
            susu_round_id: round.id.to_s,
            susu_group_id: round.susu_group.id.to_s,
            dymond_bank_payout_id: payout.id.to_s
          },
          idempotency_key: "susu-round-payout-#{round.id}"
        )

        payout.update!(status: "paid", processor_ref: transfer.id, paid_at: Time.current)
        Susu::LifecycleService.mark_round_paid_out!(round)
        payout
      rescue StandardError
        payout&.update!(status: "failed")
        round.update!(status: "funded") if round.persisted? && round.status == "processing"
        raise
      end
    end

    private

    attr_reader :round, :requested_by

    def validate!
      raise NotReady, "Round must be funded before payout" unless round.status == "funded" || round.fully_funded?
      raise NotReady, "Only the organizer can request payout" unless round.susu_group.organizer?(requested_by)
      raise NotReady, "Recipient is missing" unless round.recipient
    end
  end
end
