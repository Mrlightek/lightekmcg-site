# frozen_string_literal: true
require "test_helper"

module Studio
  module Blueprint
    class RegistrarTest < ActiveSupport::TestCase
      def definition(status: "draft", enabled: false, handler: nil)
        {
          "schema_version" => 1, "key" => "factory_registration_test",
          "name" => "Factory Registration Test", "version" => "1.0.0",
          "status" => status,
          "actions" => [{"name" => "create"}],
          "runtime" => {"enabled" => enabled, "execution_handler" => handler},
          "intent" => {"examples" => ["Make a test asset"]},
          "plan" => {"groups" => [{"key" => "build", "tasks" => ["create"]}]}
        }
      end

      def compiled(**kwargs)
        Compiler.call(source: definition(**kwargs))
      end

      teardown do
        slug = "studio.factory_registration_test.create"
        # Intelligence now references capability via a foreign key.
        # Delete the dependent test record before deleting its parent.
        NevaehIntelligence.where(intent_key: slug).delete_all
        NevaehCapability.where(slug: slug).delete_all
      end

      test "draft remains invisible even with a handler" do
        Registrar.call(blueprint: compiled(status: "draft", enabled: true, handler: "TestAdapter"))
        assert_nil Registry.resolve("studio.factory_registration_test.create")
      end

      test "published capability without binding remains unavailable" do
        Registrar.call(blueprint: compiled(status: "published", enabled: true))
        record = NevaehCapability.find_by!(slug: "studio.factory_registration_test.create")
        assert_not record.enabled?
        assert_nil Registry.resolve(record.slug)
      end

      test "publishing registers a taskable binding and drafting withdraws it" do
        Registrar.call(blueprint: compiled(status: "published", enabled: true, handler: "TestAdapter"))
        record = Registry.resolve("studio.factory_registration_test.create")
        assert_not_nil record
        assert_equal "published", record.metadata["blueprint_status"]
        assert_equal ["Make a test asset"], record.metadata.dig("intent", "examples")
        assert_equal "build", record.metadata.dig("plan", "groups", 0, "key")
        Registrar.call(blueprint: compiled(status: "draft", enabled: true, handler: "TestAdapter"))
        assert_nil Registry.resolve(record.slug)
        assert_not NevaehCapability.find(record.id).enabled?
      end

      test "registration is idempotent" do
        assert_difference "NevaehCapability.count", 1 do
          2.times { Registrar.call(blueprint: compiled(status: "published", enabled: true, handler: "TestAdapter")) }
        end
      end
    end
  end
end
