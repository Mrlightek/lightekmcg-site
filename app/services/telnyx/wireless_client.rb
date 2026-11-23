# frozen_string_literal: true

require "faraday"
require "bigdecimal"
require "json"

module Telnyx
  class WirelessClient
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end
    class Retryable < Error; end

    def initialize(connection: nil)
      @connection = connection || Faraday.new(url: "https://api.telnyx.com") do |http|
        http.headers["Authorization"] = "Bearer #{ENV.fetch('TELNYX_API_KEY')}"
        http.headers["Accept"] = "application/json"
        http.options.open_timeout = 5
        http.options.timeout = 15
        http.request :json
        http.adapter Faraday.default_adapter
      end
    end

    def purchase(group_id:, tag:)
      request(:post, "/v2/actions/purchase/esims",
        body: { amount: 1, sim_card_group_id: group_id, status: "disabled", tags: [tag] })
    end

    def find_purchase(group_id:, tag:)
      page = request(:get, "/v2/sim_cards", query: {
        "filter[sim_card_group_id]" => group_id, "filter[tags][]" => tag, "page[size]" => 50
      })
      raise Error, "SIM reconciliation returned an invalid list" unless page.is_a?(Array)

      page.select { |row| row.is_a?(Hash) && row["sim_card_group_id"] == group_id && Array(row["tags"]).include?(tag) }
    end

    def sim(id)
      object(request(:get, sim_path(id)))
    end

    def activation_code(id)
      code = object(request(:get, "#{sim_path(id)}/activation_code"))["activation_code"]
      raise Retryable, "Telnyx has not returned the activation code" unless code.is_a?(String) && UserEsim::LPA.match?(code)
      code
    end

    def set_limit(id, limit)
      card = object(request(:patch, sim_path(id), body: { data_limit: { amount: limit.to_s, unit: "MB" } }))
      data = card["data_limit"]
      amount = data && BigDecimal(data["amount"].to_s, exception: false)
      unless card["id"] == id && amount == limit && data["unit"] == "MB"
        raise Retryable, "Telnyx has not confirmed the requested limit"
      end
      card
    end

    def request_status(id, status)
      action = { "enabled" => "enable", "disabled" => "disable" }.fetch(status)
      request(:post, "#{sim_path(id)}/actions/#{action}")
    end

    private

    def sim_path(id)
      raise Error, "Invalid Telnyx SIM ID" unless UserEsim::UUID.match?(id.to_s)
      "/v2/sim_cards/#{id}"
    end

    def object(value)
      raise Retryable, "Unexpected Telnyx response structure" unless value.is_a?(Hash)
      value
    end

    def request(method, path, body: nil, query: nil)
      response = @connection.run_request(method, path, body, nil) do |request|
        request.params.update(query) if query
      end
      unless response.success?
        status = response.status
        error = status >= 500 || [408, 409, 429].include?(status) ? Retryable : Error
        raise error.new("Telnyx Wireless returned HTTP #{status}", status: status)
      end

      document = JSON.parse(response.body)
      document.fetch("data")
    rescue Faraday::Error, JSON::ParserError, KeyError, TypeError
      raise Retryable, "Telnyx Wireless request could not be confirmed", cause: nil
    end
  end
end
