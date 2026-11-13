require 'bigdecimal'
module LightekAccounting
  module Money
    LIMIT = 100_000_000_000_000
    def self.integer!(value)
      raise ArgumentError, 'Amount is outside the supported range' unless value.is_a?(Integer) && value.abs <= LIMIT
      value
    end
    def self.cents!(raw)
      value = raw.to_s.strip
      sign = 1
      if value.start_with?('(') && value.end_with?(')')
        sign = -1
        value = value[1...-1].strip
      end
      raise ArgumentError, 'Ambiguous negative amount' if sign == -1 && value.start_with?('-')
      value = value.sub(/\A(-?)\$/, '\\1')
      raise ArgumentError, 'Use a decimal amount with no more than two decimal places' unless value.match?(/\A-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?\z/)
      integer!((BigDecimal(value.delete(',')) * 100).to_i * sign)
    end
  end
end
