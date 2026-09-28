# frozen_string_literal: true

require "io/console"

SLUG = ENV.fetch("GMAIL_API_VAULT_SLUG", "gmail-api-production")

def prompt(label, secret: false)
  print "#{label}: "

  value =
    if secret
      STDIN.noecho(&:gets).to_s
    else
      STDIN.gets.to_s
    end

  puts if secret

  value.strip
end

puts
puts "=== LIGHTEK VAULT · GMAIL API CREDENTIAL STORAGE ==="
puts
puts "Secret values will not be echoed or written to this script."
puts

client_id = prompt("Google OAuth client ID")
client_secret = prompt("Google OAuth client secret", secret: true)
refresh_token = prompt("Google OAuth refresh token", secret: true)

{
  "client_id" => client_id,
  "client_secret" => client_secret,
  "refresh_token" => refresh_token,
  "sender" => sender
}.each do |key, value|
  abort "#{key} cannot be blank" if value.empty?
end

secret = LightekVault::Service.store!(
  name: "Google Gmail API Production",
  slug: SLUG,
  payload: {
    "client_id" => client_id,
    "client_secret" => client_secret,
    "refresh_token" => refresh_token,
  },
  secret_type: "credential",
  provider: "google",
  environment: "production",
  purpose: "transactional_mail",
  access_policy: {
    "consumers" => [
      "LightekMail::GmailApiDelivery"
    ],
    "purposes" => [
      "transactional_mail"
    ]
  },
  metadata: {
    "service" => "gmail_api",
    "scope" => "https://www.googleapis.com/auth/gmail.send"
  },
  requested_by: "operator"
)

puts
puts "GMAIL API VAULT SECRET STORED"
puts "slug=#{secret.slug}"
puts "provider=#{secret.provider}"
puts "environment=#{secret.environment}"
puts "status=#{secret.status}"
puts
puts "Plaintext credentials were not redisplayed."
