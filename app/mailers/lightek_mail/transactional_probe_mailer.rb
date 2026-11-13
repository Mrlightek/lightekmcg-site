# frozen_string_literal: true
module LightekMail
  class TransactionalProbeMailer < ApplicationMailer
    layout false
    def delivery_probe(recipient, reference)
      mail(to: recipient, subject: "Lightek Mail delivery check #{reference}", content_type: "text/plain",
        body: "This is a delivery check through Lightek's configured transactional mail transport.\n\nReference: #{reference}\n\nReturn to Dashboard → Settings → Automated mail delivery and confirm receipt only if this message arrived.")
    end
  end
end
