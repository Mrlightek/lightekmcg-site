# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :account_number, :routing_number, :iban, :sender, :statement, :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

Rails.application.config.filter_redirect += [%r{/passwords/}]

# Single-use provider onboarding URLs must not appear in redirect logs.
Rails.application.config.filter_redirect += ["accounts.stripe.com", "connect.stripe.com"]
