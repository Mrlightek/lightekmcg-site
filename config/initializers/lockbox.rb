# frozen_string_literal: true
# Lockbox encrypts Plaid access_token at rest on DymondBank::LinkedAccount
# Generate a master key: SecureRandom.hex(32)
# Store it in credentials or ENV — never hardcode.

Lockbox.master_key = ENV.fetch("LOCKBOX_MASTER_KEY") do
  Rails.application.credentials.lockbox_master_key
end
