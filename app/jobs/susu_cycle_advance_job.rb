# app/jobs/susu_cycle_advance_job.rb
class SusuCycleAdvanceJob < ApplicationJob
  queue_as :default

  def perform
    SusuGroup.active.find_each do |group|
      # Execute only if the current cycle deadline has passed
      next unless cycle_due?(group)

      group.transaction do
        # Log missing contributions or penalize unpaid members here
        
        # Advance payout if conditions are met
        if group.current_cycle_complete?
          group.send(:distribute_payout!)
        else
          # Handle incomplete cycle strategy (e.g., partial payout or default flag)
          Rails.logger.warn "SusuGroup ##{group.id} ended cycle ##{group.current_cycle} incomplete."
        end
      end
    end
  end

  private

  def cycle_due?(group)
    # Check if cycle time window elapsed relative to last update
    group.updated_at < 1.month.ago
  end
end