require "net/http"
require "json"
module LightekBusiness
  class ConnectSession
    class Unavailable < StandardError; end
    ENDPOINT = URI("https://api.stripe.com/v1/account_sessions")
    def self.create!(user)
      account_id = user.stripe_connect_account_id.to_s
      raise Unavailable, "Missing connected account." unless account_id.match?(/\Aacct_[A-Za-z0-9]+\z/)
      secret = ENV["STRIPE_SECRET_KEY"].presence
      raise Unavailable, "Stripe API credentials are not configured." unless secret
      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        request = Net::HTTP::Post.new(ENDPOINT)
        request.basic_auth(secret, "")
        request.set_form_data({
          "account" => account_id,
          "components[account_onboarding][enabled]" => "true",
          "components[account_management][enabled]" => "true"
        })
        http.request(request)
      end
      body = JSON.parse(response.body)
      raise Unavailable, "Stripe did not create an account session." unless response.is_a?(Net::HTTPSuccess) && body["client_secret"].is_a?(String) && body["client_secret"].length >= 20
      body.fetch("client_secret")
    rescue JSON::ParserError, IOError, SystemCallError, SocketError, Timeout::Error
      raise Unavailable, "Stripe account session could not be created."
    end
  end
end
