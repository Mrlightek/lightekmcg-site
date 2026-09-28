# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method(
    :gmail_api,
    LightekMail::GmailApiDelivery
  )
end
