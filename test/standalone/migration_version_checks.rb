# frozen_string_literal: true
require_relative "community_checks"
require File.join(ROOT, "db/migrate/20261031130001_add_client_checkout_key_to_commerce_orders")

class MigrationVersionRecoveryTest < LightekCommunityIntegrationTest
  LightekCommunityIntegrationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def test_rails_discovers_all_migrations_without_duplicate_versions
    migrations = ActiveRecord::MigrationContext.new(File.join(ROOT, "db/migrate")).migrations
    assert_equal migrations.length, migrations.map(&:version).uniq.length
    assert_includes migrations.map(&:version), 20261031130001
    assert_includes migrations.map(&:version), 20261031130002
    assert_includes migrations.map(&:version), 20261031140001
    assert_includes migrations.map(&:version), 20261031140002
  end

  def test_preexisting_studio_and_top_people_survive_reconciliation
    project = StudioProject.create!(owner: @alice, site: @site, name: "Existing production")
    @alice.profile.update!(community_gender: "woman", top_people_limit: 5)
    top = LightekSocial::TopPerson.create!(profile: @alice.profile, person: @bob.profile, position: 1)
    Post.create!(user: @alice, site: @site, content: "Existing discussion", audience: "women")
    2.times do
      PersistLightekStudioWorkspaces.new.migrate(:up)
      IntegrateProfileTopPeopleAndAudiences.new.migrate(:up)
    end
    assert_equal @alice.id, project.reload.owner_id
    assert_equal "woman", @alice.profile.reload.community_gender
    assert_equal 5, @alice.profile.top_people_limit
    assert_equal @bob.profile.id, top.reload.person_id
    assert_equal "women", Post.first.audience
    ActiveRecord::Base.connection.remove_index(:lightek_social_top_people, name: "idx_top_people_position")
    IntegrateProfileTopPeopleAndAudiences.new.migrate(:up)
    assert ActiveRecord::Base.connection.index_exists?(:lightek_social_top_people, %i[profile_id position], unique: true)
  end

  def test_checkout_reconciliation_handles_new_and_preexisting_columns
    connection = ActiveRecord::Base.connection
    connection.create_table(:lightek_commerce_orders) { |t| t.string :customer_email }
    migration = AddClientCheckoutKeyToCommerceOrders.new
    migration.migrate(:up)
    connection.execute("INSERT INTO lightek_commerce_orders (customer_email,client_checkout_key) VALUES ('buyer@example.test','existing-checkout')")
    migration.migrate(:up)
    assert_equal "existing-checkout", connection.select_value("SELECT client_checkout_key FROM lightek_commerce_orders")
    assert connection.index_exists?(:lightek_commerce_orders, %i[customer_email client_checkout_key], unique: true)
    connection.remove_index(:lightek_commerce_orders, name: "idx_commerce_client_checkout_key")
    migration.migrate(:up)
    assert connection.index_exists?(:lightek_commerce_orders, %i[customer_email client_checkout_key], unique: true)
  end
end
