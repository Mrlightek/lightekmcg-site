class SusuInvitationsController < ApplicationController
  allow_unauthenticated_access only: :accept

  def accept
    invitation = SusuInvitation.find_by_invitation_token!(params[:token])

    if invitation.expired?
      redirect_to susu_path, alert: "This Susu invitation has expired."
    elsif authenticated?
      invitation.accept_for!(current_user)
      redirect_to susu_group_path(invitation.susu_group), notice: "You joined #{invitation.susu_group.name}."
    else
      redirect_to susu_signup_path(invite: params[:token])
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to susu_path, alert: "That Susu invitation is invalid or has expired."
  rescue ArgumentError => e
    redirect_to susu_path, alert: e.message
  end
end
