# app/controllers/susu_groups_controller.rb
class SusuGroupsController < ApplicationController
  before_action :set_susu_group, only: %i[show edit update activate contribution contribute request_exit]
  before_action :require_organizer!, only: %i[edit update activate]

  def index
    @organized_susus = SusuGroup.where(organizer: current_user).order(updated_at: :desc)
    @member_susus = SusuGroup.joins(:susu_memberships)
                            .where(susu_memberships: { user_id: current_user.id })
                            .where.not(organizer_id: current_user.id)
                            .distinct
                            .order(updated_at: :desc)
  end

  def new
    @susu_group = SusuGroup.new(
      contribution_amount: 100,
      cycle_frequency: "monthly",
      target_member_count: 2
    )
  end

  def create
    @susu_group = SusuGroup.new(susu_group_params.merge(organizer: current_user))

    SusuGroup.transaction do
      @susu_group.save!
      @susu_group.susu_memberships.create!(user: current_user, payout_position: 1)
      LightekEmailProvisioningService.provision_for!(current_user)
    end

    redirect_to @susu_group, notice: "Susu created. Add your members, confirm the payout order, then activate it."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @memberships = @susu_group.susu_memberships.includes(:user).order(:payout_position)
    @current_user_membership = @memberships.find { |membership| membership.user_id == current_user.id }
    @current_contribution = @susu_group.contribution_for_current_cycle(current_user) if @current_user_membership
    @cycle = @susu_group.current_cycle_record
    @round = @susu_group.current_round_record
    @commitment = @susu_group.outstanding_commitment_for(current_user) if @current_user_membership
  end

  def edit
  end

  def update
    if @susu_group.update(susu_group_params)
      redirect_to @susu_group, notice: "Susu settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def activate
    unless @susu_group.ready_to_activate?
      redirect_to @susu_group,
                  alert: "Add all #{@susu_group.target_member_count} members and complete the payout order before activating."
      return
    end

    Susu::LifecycleService.activate!(@susu_group)
    redirect_to @susu_group, notice: "Susu activated. Cycle 1, Round 1 contributions are now open."
  end

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
      description: "#{@susu_group.name} — Cycle #{@susu_group.current_cycle}, Round #{@susu_group.current_round_number} contribution",
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

  def request_exit
    membership = @susu_group.susu_memberships.find_by!(user: current_user)
    commitment = Susu::LifecycleService.request_exit!(membership)

    if commitment&.remaining_amount.to_d&.positive?
      redirect_to @susu_group,
                  notice: "Exit requested. Your remaining Susu obligation is #{helpers.number_to_currency(commitment.remaining_amount)} and is not cancelled by the request."
    else
      redirect_to @susu_group, notice: "Exit requested."
    end
  end

  private

  def set_susu_group
    @susu_group = SusuGroup.find(params[:id])
  end

  def require_organizer!
    return if @susu_group.organizer?(current_user)

    redirect_to @susu_group, alert: "Only the Susu organizer can change this group."
  end

  def susu_group_params
    params.require(:susu_group).permit(:name, :contribution_amount, :cycle_frequency, :target_member_count)
  end
end
