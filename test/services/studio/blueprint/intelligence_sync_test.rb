# frozen_string_literal: true
require "test_helper"

module Studio
  module Blueprint
    class IntelligenceSyncTest < ActiveSupport::TestCase
      class RunnableHandler
        def self.perform(_action, _payload); { "ok" => true }; end
      end

      def source(status: "draft", handler: nil, enabled: false, name: "Intelligent Factory")
        {
          "schema_version" => 1,
          "key" => "intelligence_factory_test",
          "name" => name,
          "version" => "1.0.0",
          "status" => status,
          "actions" => [{ "name" => "create" }],
          "runtime" => { "enabled" => enabled, "execution_handler" => handler },
          "metadata" => { "target_model" => "StudioProject" }
        }
      end

      def register(**options)
        Registrar.call(blueprint: Compiler.call(source: source(**options)))
      end

      def slug
        "studio.intelligence_factory_test.create"
      end

      teardown do
        NevaehIntelligence.where(intent_key: slug).delete_all
        NevaehCapability.where(slug: slug).delete_all
      end

      test "draft blueprint synchronizes unavailable intelligence" do
        register
        intelligence = NevaehIntelligence.find_by!(intent_key: slug)
        assert_equal "draft", intelligence.status
        assert_equal "StudioProject", intelligence.target_model
        assert_equal "create", intelligence.instructions["action"]
        assert_equal slug, intelligence.nevaeh_capability.slug
        assert_not_includes NevaehIntelligence.available.pluck(:intent_key), slug
      end

      test "published executable capability becomes discoverable" do
        register(status: "published", enabled: true, handler: RunnableHandler.name)
        intelligence = NevaehIntelligence.available.find_by!(intent_key: slug)
        assert_equal "published", intelligence.status
        assert_equal true, intelligence.metadata["execution_ready"]
        assert_equal "preview", NevaehIntelligences::Dispatch.call(intent_key: slug)["status"]
      end

      test "published missing executable handler stays unavailable" do
        register(status: "published", enabled: true, handler: "MissingFactoryHandler")
        assert_equal "draft", NevaehIntelligence.find_by!(intent_key: slug).status
        assert_not_includes NevaehIntelligence.available.pluck(:intent_key), slug
      end

      test "registration updates same intelligence and withdrawing publication disables it" do
        register(status: "published", enabled: true, handler: RunnableHandler.name)
        first = NevaehIntelligence.find_by!(intent_key: slug)
        assert_no_difference "NevaehIntelligence.count" do
          register(status: "published", enabled: true, handler: RunnableHandler.name, name: "Renamed Factory")
        end
        assert_equal first.id, NevaehIntelligence.find_by!(intent_key: slug).id
        assert_match(/Renamed Factory/, first.reload.name)
        register(status: "archived", enabled: true, handler: RunnableHandler.name)
        assert_equal "archived", first.reload.status
        assert_not_includes NevaehIntelligence.available.pluck(:intent_key), slug
      end

      test "refuses to take over an intelligence owned by someone else" do
        foreign = NevaehCapability.create!(name: "Manual", slug: "studio.manual.intelligence_test", domain: "studio",
          intent_name: "manual_test", handler: "Studio::Workers::Pwa", queue: "default", priority: 5, enabled: false)
        NevaehIntelligence.create!(name: "Manual", intent_key: slug, operation: "create", status: "draft",
          nevaeh_capability: foreign, metadata: { "studio_blueprint_key" => "elsewhere" })
        assert_raises(ArgumentError) { register }
        assert_nil NevaehCapability.find_by(slug: slug)
      ensure
        NevaehIntelligence.where(intent_key: slug).delete_all
        NevaehCapability.where(slug: "studio.manual.intelligence_test").delete_all
      end
    end
  end
end
