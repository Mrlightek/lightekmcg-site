class ApplicationMailbox < ActionMailbox::Base
  # Route all incoming emails to Nevaeh's processing Mailbox
  routing /.*/ => :nevaeh_ingress
end