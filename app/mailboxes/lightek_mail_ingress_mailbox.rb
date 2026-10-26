class LightekMailIngressMailbox < ApplicationMailbox
  def process
    LightekMail::Inbound.process!(inbound_email)
  end
end
