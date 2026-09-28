# frozen_string_literal: true

require_relative "../config/environment"
require "mail"

def clean_email(value)
  value.to_s
       .strip
       .gsub(/\A['"‘’“”]+|['"‘’“”]+\z/, "")
       .strip
end

recipient = clean_email(ENV.fetch("TEST_EMAIL"))
sender    = clean_email(ENV.fetch("GOOGLE_GMAIL_SENDER"))

raise "Invalid TEST_EMAIL: #{recipient.inspect}" unless recipient.match?(URI::MailTo::EMAIL_REGEXP)
raise "Invalid GOOGLE_GMAIL_SENDER: #{sender.inspect}" unless sender.match?(URI::MailTo::EMAIL_REGEXP)

message = Mail.new do
  from    sender
  to      recipient
  subject "Lightek Gmail API delivery test"

  body <<~BODY
    Lightek Gmail API delivery is working.

    This message was sent from Rails through the Gmail API over HTTPS.
  BODY
end

raise "Message has no From header" if message.from.blank?
raise "Message has no To header" if message.to.blank?

puts
puts "===== MESSAGE CHECK ====="
puts "from=#{message.from.inspect}"
puts "to=#{message.to.inspect}"
puts "subject=#{message.subject.inspect}"

message.delivery_method(LightekMail::GmailApiDelivery)
message.deliver!

puts
puts "GMAIL API TEST SEND COMPLETE"
puts "from=#{sender}"
puts "to=#{recipient}"
