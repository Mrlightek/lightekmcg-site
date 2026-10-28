# frozen_string_literal: true
module LightekMarketing
  class SubscriptionMailer < ApplicationMailer
    def confirm(contact_id, token)
      @contact = Contact.find(contact_id)
      @url = confirm_marketing_subscription_url(token: token)
      mail(to: @contact.email, subject: "Confirm your subscription")
    end
  end
end
