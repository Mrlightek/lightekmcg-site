# frozen_string_literal: true

require "test_helper"

module Studio
  module Blueprint
    class RuntimeTest < ActiveSupport::TestCase
      test "refuses direct execution while blueprint runtime is disabled" do
        error =
          assert_raises(
            Runtime::BlueprintDisabled
          ) do
            Runtime.perform(
              blueprint_key:
                "example_asset",
              action:
                "create",
              payload: {
                "name" =>
                  "Safety Test"
              }
            )
          end

        assert_match(
          /example_asset/,
          error.message
        )

        assert_match(
          /disabled/,
          error.message
        )
      end

      test "rejects actions outside the canonical blueprint contract" do
        error =
          assert_raises(
            ArgumentError
          ) do
            Runtime.perform(
              blueprint_key:
                "example_asset",
              action:
                "destroy",
              payload:
                {}
            )
          end

        assert_match(
          /Unsupported example_asset Studio blueprint action/,
          error.message
        )

        assert_match(
          /create/,
          error.message
        )
      end
    end
  end
end
