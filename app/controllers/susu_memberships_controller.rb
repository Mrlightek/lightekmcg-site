class SusuMembershipsController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :set_susu_group
  before_action :require_organizer!

  def create
    if @susu_group.active? || @susu_group.completed?
      redirect_to @susu_group, alert: "Members cannot be added after the Susu is activated."
      return
    end

    email = params.dig(:susu_membership, :email_address).to_s.strip.downcase
    user = User.find_by("LOWER(email_address) = ?", email)

    unless user
      redirect_to @susu_group,
                  alert: "No Lightek account exists for #{email}. Account invitations are the next onboarding step."
      return
    end

    if @susu_group.members.exists?(id: user.id)
      redirect_to @susu_group, alert: "That person is already a member of this Susu."
      return
    end

    if @susu_group.members.count >= @susu_group.target_member_count
      redirect_to @susu_group, alert: "This Susu already has its #{@susu_group.target_member_count} members."
      return
    end

    @susu_group.susu_memberships.create!(
      user: user,
      payout_position: @susu_group.next_payout_position
    )
    LightekEmailProvisioningService.provision_for!(user)

    redirect_to @susu_group, notice: "#{member_label(user)} joined the Susu."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @susu_group, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    membership = @susu_group.susu_memberships.find(params[:id])
    membership.update!(payout_position: params.require(:susu_membership).fetch(:payout_position))
    redirect_to @susu_group, notice: "Payout position updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @susu_group, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    membership = @susu_group.susu_memberships.find(params[:id])

    if membership.user_id == @susu_group.organizer_id
      redirect_to @susu_group, alert: "The organizer cannot be removed from the Susu."
      return
    end

    if @susu_group.active? || @susu_group.completed?
      redirect_to @susu_group, alert: "Members cannot be removed after the Susu is activated."
      return
    end

    membership.destroy!
    normalize_payout_positions!
    redirect_to @susu_group, notice: "Member removed."
  end

  private

  def set_susu_group
    @susu_group = SusuGroup.find(params[:susu_group_id])
  end

  def require_organizer!
    return if @susu_group.organizer?(current_user)

    redirect_to @susu_group, alert: "Only the Susu organizer can manage members."
  end

  def normalize_payout_positions!
    @susu_group.susu_memberships.order(:payout_position).each_with_index do |membership, index|
      membership.update_column(:payout_position, index + 1)
    end
  end

  def member_label(user)
    return user.full_name if user.respond_to?(:full_name) && user.full_name.present?

    user.email_address
  end
end
