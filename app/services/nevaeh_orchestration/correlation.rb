# frozen_string_literal: true

require "securerandom"

module NevaehOrchestration
  module Correlation
    module_function

    def generate
      SecureRandom.uuid
    end

    def normalize(value)
      value.to_s.strip.presence || generate
    end
  end
end
