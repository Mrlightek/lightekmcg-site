require_relative 'community_checks'
require 'minitest/mock'
ActiveRecord::Schema.define do
  create_table(:nevaeh_capabilities) do |t|
    %i[name slug domain intent_name description subject_type handler queue gatekeeper_capability].each { |c| t.string c }
    t.integer :priority
    t.boolean :enabled
    %i[event_types intent_patterns knowledge_article_ids].each { |c| t.json c, default: [] }
    %i[expected_outcome failure_policy realtime input_adapter metadata].each { |c| t.json c, default: {} }
  end
  add_index :nevaeh_capabilities, :slug, unique: true
end
class NevaehCapability < ApplicationRecord; end
require File.join(ROOT, 'app/services/lightek_pwa/member_runtime')
class PwaMemberRuntimeChecks < Minitest::Test
  def setup
    @old = ENV['LIGHTEK_PWA_MEMBER_BACKEND']
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
    LightekPwa::NavigationItem.delete_all
    LightekPwa::SurfaceModule.delete_all
    LightekPwa::Surface.delete_all
    NevaehCapability.delete_all
    @root = Rails.application.config.root
    Rails.application.config.root = Pathname.new(ROOT)
  end
  def teardown
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = @old
    Rails.application.config.root = @root
  end
  def test_fresh_member_gets_real_page_navigation_and_publishing_contracts
    assert LightekPwa::MemberRuntime.prepare!
    assert LightekPwa::Surface.find_by!(key: 'create').enabled
    assert LightekPwa::Surface.find_by!(key: 'space').enabled
    assert LightekPwa::NavigationItem.find_by!(key: 'create').enabled
    %w[community.post.create messages.send social.people.recommend studio.pwa.bootstrap studio.workspace.assets.list].each do |slug|
      assert NevaehCapability.find_by!(slug: slug).enabled, slug
    end
  end
  def test_update_preserves_existing_disabled_and_custom_entries
    LightekPwa::MemberRuntime.prepare!
    page = LightekPwa::Surface.find_by!(key: 'create')
    page.update!(enabled: false, label: 'Owner choice')
    capability = NevaehCapability.find_by!(slug: 'community.post.create')
    capability.update!(enabled: false, description: 'Operator choice')
    before = [LightekPwa::Surface.count, NevaehCapability.count]
    LightekPwa::MemberRuntime.prepare!
    assert_equal before, [LightekPwa::Surface.count, NevaehCapability.count]
    assert_equal [false, 'Owner choice'], page.reload.attributes.values_at('enabled', 'label')
    assert_equal [false, 'Operator choice'], capability.reload.attributes.values_at('enabled', 'description')
  end
  def test_seed_failure_rolls_back_page_initialization
    NevaehCapability.stub(:find_or_initialize_by, ->(**) { raise 'seed boundary failed' }) do
      assert_raises(RuntimeError) { LightekPwa::MemberRuntime.prepare! }
    end
    assert_empty LightekPwa::Surface.all
    assert_empty LightekPwa::NavigationItem.all
    assert_empty NevaehCapability.all
  end
  def test_partial_registry_gets_social_picker_without_resetting_disabled_contracts
    NevaehCapability.create!(slug: 'messages.send', enabled: false, description: 'Owner disabled')
    LightekPwa::MemberRuntime.prepare!
    assert NevaehCapability.find_by!(slug: 'social.people.recommend').enabled
    assert_equal [false, 'Owner disabled'], NevaehCapability.find_by!(slug: 'messages.send').attributes.values_at('enabled', 'description')
    ENV['LIGHTEK_PWA_SEED_MISSING_ONLY'] = 'prior-value'
    LightekPwa::MemberRuntime.prepare!
    assert_equal 'prior-value', ENV['LIGHTEK_PWA_SEED_MISSING_ONLY']
  ensure
    ENV.delete('LIGHTEK_PWA_SEED_MISSING_ONLY')
  end
  def test_nonmember_databases_are_untouched
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'false'
    refute LightekPwa::MemberRuntime.prepare!
    assert_empty LightekPwa::Surface.all
    assert_empty NevaehCapability.all
  end
end
