# frozen_string_literal: true
# Review-only metadata transformation with no database or network effects.
module NevaehGenerated
  module MetadataNormalizer
    module_function
    def call(input)
      raise ArgumentError, "metadata must be a Hash" unless input.is_a?(Hash)
      raise ArgumentError, "too many fields" if input.size > 40
      result = {}
      input.each do |key, value|
        raise ArgumentError, "invalid field name" unless key.is_a?(String) && /\A[a-z][a-z0-9_]{0,63}\z/.match?(key)
        raise ArgumentError, "invalid field value" unless value.is_a?(String) && value.bytesize <= 512
        result[key] = value.strip.gsub(/[[:space:]]+/, " ")
      end
      result.sort.to_h.freeze
    end
  end
end
