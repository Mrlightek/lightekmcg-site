require "bigdecimal"
module LightekShipping
  module Payload
    module_function
    # Launch with domestic U.S. parcels. International services need customs,
    # duties and commodity declarations before they can be enabled.
    def party!(input)
      value = input.to_h.deep_stringify_keys
      required = %w[name phone street city state postal_code country]
      raise ArgumentError, "Complete the shipping name, phone and U.S. address" unless required.all? { |key| value[key].is_a?(String) && value[key].strip.present? && value[key].length <= 150 && value[key].ascii_only? && !value[key].match?(/[\x00-\x1f]/) }
      raise ArgumentError, "Domestic U.S. shipping is currently supported" unless value["country"] == "US" && value["state"].match?(/\A[A-Z]{2}\z/) && value["postal_code"].match?(/\A\d{5}(?:-\d{4})?\z/)
      {"contact" => {"personName" => value["name"], "phoneNumber" => value["phone"]},
        "address" => {"streetLines" => [value["street"]], "city" => value["city"], "stateOrProvinceCode" => value["state"],
          "postalCode" => value["postal_code"], "countryCode" => "US", "residential" => !%w[false 0].include?(value.fetch("residential", true).to_s)}}
    end
    def package!(input)
      value = input.to_h.deep_stringify_keys
      weight = BigDecimal(value.fetch("weight_lb").to_s)
      dims = %w[length_in width_in height_in].map { |key| Integer(value.fetch(key)) }
      raise ArgumentError, "Package needs positive weight and dimensions" unless weight.positive? && weight <= 150 && dims.all? { |length| length.between?(1, 108) }
      {"weight" => {"units" => "LB", "value" => weight.to_f},
        "dimensions" => {"length" => dims[0], "width" => dims[1], "height" => dims[2], "units" => "IN"}, "groupPackageCount" => 1}
    rescue KeyError, TypeError
      raise ArgumentError, "Package needs weight, length, width and height"
    end
    def shipment!(origin:, recipient:, packages:)
      raise ArgumentError, "Use between 1 and 40 parcels" unless packages.is_a?(Array) && packages.size.between?(1, 40)
      {"shipper" => party!(origin), "recipients" => [party!(recipient)], "pickupType" => "DROPOFF_AT_FEDEX_LOCATION",
        "packagingType" => "YOUR_PACKAGING", "rateRequestType" => ["ACCOUNT"], "totalPackageCount" => packages.size,
        "requestedPackageLineItems" => packages.map { |package| package!(package) }}
    end
  end
end
