# frozen_string_literal: true

module Susu
  class LifecycleService
    TERMS_VERSION = "dymond-susu-v2".freeze

    class << self
      def activate!(group)
        raise ArgumentError, "Susu must be a draft" unless group.draft?
        raise ArgumentError, "Susu is not ready to activate" unless group.ready_to_activate?

        group.transaction do
          group.update!(status: :active, current_cycle: 1, current_round_number: 1)

          cycle = group.susu_cycles.create!(
            number: 1,
            status: "active",
            starts_at: Time.current
          )

          memberships = group.susu_memberships.order(:payout_position).to_a
          rounds = memberships.length

          memberships.each do |membership|
            membership.update!(joined_at: membership.joined_at || Time.current)
            membership.susu_commitments.create!(
              susu_cycle: cycle,
              contribution_amount: group.contribution_amount,
              rounds_committed: rounds,
              remaining_amount: group.contribution_amount * rounds,
              accepted_at: Time.current,
              terms_version: TERMS_VERSION,
              status: "active"
            )
          end

          memberships.each_with_index do |membership, index|
            number = index + 1
            cycle.susu_rounds.create!(
              number: number,
              recipient_membership: membership,
              due_at: due_at_for(group, cycle.starts_at, number),
              status: number == 1 ? "open" : "scheduled",
              expected_pot: group.contribution_amount * memberships.length,
              collected_amount: 0
            )
          end

          cycle
        end
      end

      def settle_contribution!(contribution)
        group = contribution.susu_group
        membership = contribution.susu_membership ||
                     group.susu_memberships.find_by!(user_id: contribution.user_id)
        round = contribution.susu_round || group.current_round_record
        raise "No active Susu round exists" unless round

        contribution.transaction do
          contribution.update!(
            status: "succeeded",
            paid_at: Time.current,
            failure_message: nil,
            susu_membership: membership,
            susu_round: round,
            cycle_number: round.susu_cycle.number,
            round_number: round.number
          )

          commitment = membership.susu_commitments
                                 .where(susu_cycle: round.susu_cycle)
                                 .open
                                 .order(created_at: :desc)
                                 .first
          commitment&.apply_settlement!(contribution.amount)

          round.refresh_collected_amount!
          round.update!(status: round.fully_funded? ? "funded" : "funding")
        end

        contribution
      end

      def mark_round_paid_out!(round)
        group = round.susu_group
        cycle = round.susu_cycle

        group.transaction do
          raise "Round is not fully funded" unless round.fully_funded?

          round.update!(status: "paid_out", paid_out_at: Time.current)
          round.recipient_membership.update!(payout_received: true)

          next_round = cycle.susu_rounds.where("number > ?", round.number).order(:number).first

          if next_round
            next_round.update!(status: "open")
            group.update!(current_round_number: next_round.number)
          else
            cycle.update!(status: "completed", completed_at: Time.current)
            group.update!(status: :completed)
          end
        end
      end

      def request_exit!(membership)
        membership.update!(exit_requested_at: Time.current)
        membership.susu_commitments.open.order(created_at: :desc).first
      end

      private

      def due_at_for(group, starts_at, round_number)
        offset = round_number - 1

        case group.cycle_frequency
        when "weekly" then starts_at + offset.weeks
        when "biweekly" then starts_at + (offset * 2).weeks
        when "monthly" then starts_at + offset.months
        else starts_at
        end
      end
    end
  end
end
