class ApplicationMailbox < ActionMailbox::Base
  routing ->(email) { LightekMail::Envelope.exists?(inbound_email_id: email.id) } => :lightek_mail_ingress
  # Route all incoming emails to Nevaeh's processing Mailbox
  routing /.*/ => :nevaeh_ingress
end
