class MemberEmailMailer < ApplicationMailer
  def confirmation(user, origin)
    @url = origin + '/member-email/confirm?token=' + ERB::Util.url_encode(user.generate_token_for(:email_verification))
    mail(to: user.email_address, subject: 'Confirm your Lightek email account') do |format|
      format.text { render plain: "Confirm the email you used to sign up before creating your Lightek inbox.\n\n#{@url}\n\nThis link expires in two days. If you did not request an inbox, you can ignore this message." }
    end
  end
end
