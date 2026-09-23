# frozen_string_literal: true

module Susu
  class MatchingService
    class << self
      def suggestions_for(preference, limit: 20)
        SusuMatchPreference
          .where(status: "open")
          .where.not(user_id: preference.user_id)
          .where(
            contribution_amount: preference.contribution_amount,
            cycle_frequency: preference.cycle_frequency,
            desired_member_count: preference.desired_member_count
          )
          .order(created_at: :asc)
          .limit(limit)
      end

      def enough_for_circle?(preference)
        needed = preference.desired_member_count - 1
        suggestions_for(preference, limit: needed).count >= needed
      end

      def proposed_members(preference)
        needed = preference.desired_member_count - 1
        [preference] + suggestions_for(preference, limit: needed).to_a
      end
    end
  end
end
