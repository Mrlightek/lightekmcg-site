module Gatekeeper
  module Compute
    class ApprovalService
      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        return request if request.compute_provider.blank?

        if request.estimated_monthly_cost_cents.nil?
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_cost",
            approval_reason: "Monthly cost estimate is required before automatic approval can be evaluated."
          )
          return request
        end

        policy = request.compute_policy

        if policy.blank?
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "No compute policy is attached; human approval is required."
          )
          return request
        end

        if policy.monthly_cost_ceiling_cents.present? &&
           request.estimated_monthly_cost_cents > policy.monthly_cost_ceiling_cents
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "Estimated monthly cost exceeds policy ceiling."
          )
          return request
        end

        if policy.approval_required_for?(request.estimated_monthly_cost_cents)
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "Estimated monthly cost exceeds automatic approval ceiling."
          )
        else
          request.update!(
            approval_status: "auto_approved",
            execution_status: "ready",
            approval_reason: "Automatically approved under compute policy #{policy.slug}.",
            approved_by: "nevaeh/policy",
            approved_at: Time.current
          )
        end

        request
      end

      private

      attr_reader :request, :requested_by
    end
  end
end
