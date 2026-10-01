# frozen_string_literal: true

module Susu
  module Workers
    class Pwa
      class AccessDenied < StandardError; end

      def self.perform(action, payload = {})
        new(
          action: action,
          payload: payload
        ).perform
      end

      def initialize(action:, payload:)
        @action = action.to_s
        @payload =
          payload.to_h.deep_stringify_keys
      end

      def perform
        case action
        when "list"
          list
        when "show"
          show
        when "contribution_quote"
          contribution_quote
        when "contribution_checkout"
          contribution_checkout
        else
          raise ArgumentError,
                "Unsupported Susu action: #{action}"
        end
      end

      private

      attr_reader :action, :payload

      def user
        @user ||=
          User.find(
            payload.fetch("user_id")
          )
      end

      def group
        @group ||=
          SusuGroup.find(
            payload.fetch("group_id")
          )
      end

      def accessible_groups
        organized =
          SusuGroup.where(
            organizer_id: user.id
          )

        member =
          SusuGroup
            .joins(:susu_memberships)
            .where(
              susu_memberships: {
                user_id: user.id
              }
            )

        SusuGroup
          .where(
            id: organized.select(:id)
          )
          .or(
            SusuGroup.where(
              id: member.select(:id)
            )
          )
          .distinct
      end

      def authorize_group!
        allowed =
          group.organizer?(user) ||
          group.susu_memberships.exists?(
            user_id: user.id
          )

        raise AccessDenied,
              "You do not have access to this Susu" \
          unless allowed

        group
      end

      def authorize_contribution!
        authorize_group!

        unless group.susu_memberships.exists?(
          user_id: user.id
        )
          raise AccessDenied,
                "You are not a member of this Susu"
        end

        raise AccessDenied,
              "Susu is not active" \
          unless group.active?

        group
      end

      def list
        groups =
          accessible_groups
            .order(updated_at: :desc)
            .map do |record|
              group_payload(record)
            end

        {
          "groups" => groups
        }
      end

      def show
        authorize_group!

        {
          "group" =>
            group_payload(
              group,
              detailed: true
            )
        }
      end

      def contribution_quote
        authorize_contribution!

        quote =
          DymondBank::PaymentQuote.call(
            principal_cents:
              Money
                .from_amount(
                  group.contribution_amount
                )
                .cents,

            rail: :stripe_ach,
            context: :susu
          )

        {
          "quote" => quote.to_h
        }
      end

      def contribution_checkout
        authorize_contribution!

        contribution =
          group
            .build_contribution_for_payment!(
              user
            )

        session =
          DymondBank::StripeCheckoutService
            .create_for_payable!(
              payable: contribution,
              payer: user,

              principal_cents:
                Money
                  .from_amount(
                    contribution.amount
                  )
                  .cents,

              context: :susu,

              description:
                "#{group.name} — " \
                "Cycle #{group.current_cycle} " \
                "contribution",

              success_url:
                payload.fetch(
                  "success_url"
                ),

              cancel_url:
                payload.fetch(
                  "cancel_url"
                )
            )

        {
          "checkout_url" => session.url,
          "contribution_id" =>
            contribution.id
        }
      end

      def group_payload(record, detailed: false)
        result = {
          "id" => record.id,
          "name" => record.name,
          "status" => record.status,

          "contribution_cents" =>
            Money
              .from_amount(
                record.contribution_amount
              )
              .cents,

          "cycle_frequency" =>
            record.cycle_frequency,

          "current_cycle" =>
            record.current_cycle,

          "member_count" =>
            record.susu_memberships.count,

          "target_member_count" =>
            record.target_member_count,

          "organizer" =>
            record.organizer_id == user.id
        }

        if detailed
          result["payment_state"] =
            if record
                 .susu_memberships
                 .exists?(
                   user_id: user.id
                 )
              record
                .payment_state_for(user)
                .to_s
            end

          result["members"] =
            record
              .susu_memberships
              .includes(:user)
              .order(:payout_position)
              .map do |membership|
                {
                  "user_id" =>
                    membership.user_id,

                  "payout_position" =>
                    membership.payout_position,

                  "name" =>
                    member_name(
                      membership.user
                    )
                }
              end
        end

        result
      end

      def member_name(member)
        if member.respond_to?(:full_name) &&
           member.full_name.present?
          member.full_name
        elsif member.respond_to?(:email_address)
          member.email_address
        else
          "Member"
        end
      end
    end
  end
end
