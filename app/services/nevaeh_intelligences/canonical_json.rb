# frozen_string_literal: true
require 'json'
module NevaehIntelligences
  module CanonicalJSON
    module_function
    def normalize(value)
      case value
      when Hash then value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, normalize(value.fetch(key))] }
      when Array then value.map { |item| normalize(item) }
      else value
      end
    end
    def dump(value) = JSON.generate(normalize(value))
  end
end
