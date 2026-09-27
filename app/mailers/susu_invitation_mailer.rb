class SusuInvitationMailer < ApplicationMailer
  def invite
    @invitation = params.fetch(:invitation)
    @group = @invitation.susu_group
    @inviter = @invitation.inviter
    @invite_url = accept_susu_invitation_url(token: @invitation.invitation_token)

    mail(
      to: @invitation.email_address,
      from: ENV.fetch("MAIL_FROM", "Susu by Lightek <susu@lightekmcg.com>"),
      subject: "#{@inviter.full_name} invited you to join #{@group.name}"
    )
  end
end
