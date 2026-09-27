class SusuRegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @invitation = invitation_from_params
    @user = User.new(email_address: @invitation&.email_address)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    @invitation = nil
    @user = User.new
  end

  def create
    @invitation = invitation_from_params
    @user = User.new(registration_params.merge(role: "client"))

    User.transaction do
      @user.save!
      @user.grant_feature!(:susu, source: @invitation ? "susu_invitation_signup" : "susu_public_signup")
      @invitation&.accept_for!(@user)
    end

    start_new_session_for(@user)
    redirect_to(@invitation ? susu_group_path(@invitation.susu_group) : new_susu_group_path,
                notice: @invitation ? "Account created and invitation accepted." : "Welcome to Susu.")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @user ||= User.new
    @user.errors.add(:base, e.message) if @user.errors.empty?
    render :new, status: :unprocessable_entity
  end

  private

  def invitation_from_params
    return unless params[:invite].present?
    SusuInvitation.find_by_invitation_token!(params[:invite])
  end

  def registration_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :phone, :password, :password_confirmation)
  end
end
