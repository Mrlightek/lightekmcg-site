# app/controllers/susu_groups_controller.rb
class SusuGroupsController < ApplicationController
  before_action :set_susu_group, only: [:show, :contribution, :contribute]

  def show
  end

  # First-class Susu payment surface. This is intentionally not an invoice page.
  def contribution
    authorize! :contribute, @susu_group

    @existing_contribution = @susu_group.contribution_for_current_cycle(current_user)
    @payment_quote = DymondBank::PaymentQuote.call(
      principal_cents: Money.from_amount(@susu_group.contribution_amount).cents,
      rail: :stripe_ach,
      context: :susu
    )
  end

  def contribute
    authorize! :contribute, @susu_group

    contribution = @susu_group.build_contribution_for_payment!(current_user)

    session = DymondBank::StripeCheckoutService.create_for_payable!(
      payable: contribution,
      payer: current_user,
      principal_cents: Money.from_amount(contribution.amount).cents,
      context: :susu,
      description: "#{@susu_group.name} — Cycle #{@susu_group.current_cycle} contribution",
      success_url: contribution_susu_group_url(@susu_group, payment: "processing"),
      cancel_url: contribution_susu_group_url(@susu_group, payment: "cancelled")
    )

    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue DymondBank::StripeCheckoutService::ConfigurationError, Stripe::StripeError => e
    Rails.logger.error "[Susu] Stripe checkout failed for group #{@susu_group&.id}: #{e.message}"
    redirect_to contribution_susu_group_path(@susu_group), alert: "Payment could not be started: #{e.message}"
  rescue StandardError => e
    redirect_to contribution_susu_group_path(@susu_group), alert: e.message
  end

  private

  def set_susu_group
    @susu_group = SusuGroup.find(params[:id])
  end
end
