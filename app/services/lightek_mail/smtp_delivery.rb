# frozen_string_literal: true
require "mail"
module LightekMail
  # Transactional messages use the same transport as the Lightek inbox.
  # No Google credential lookup and no fallback to another provider.
  class SmtpDelivery
    attr_reader :settings
    def initialize(settings = {}) = @settings = settings
    def deliver!(mail)
      Mail::SMTP.new(Transport.settings.merge(settings)).deliver!(mail)
    end
  end
end
