require 'minitest/autorun'
require 'minitest/mock'
require 'active_record'
require 'pathname'

ROOT = Pathname.new(File.expand_path('../..', __dir__))
module Rails
  def self.application = @application
  def self.application=(app)
    @application = app
  end
end
module DymondSite; end

class SiteInitializerTest < Minitest::Test
  class PrepareFixture
    attr_reader :callback
    def to_prepare(&block)
      @callback = block
    end
  end

  def setup
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    DymondSite.const_set(:Site, Class.new(ActiveRecord::Base) { self.table_name = 'dymond_site_sites' })
    @reloader = PrepareFixture.new
    Rails.application = Struct.new(:reloader).new(@reloader)
    load ROOT.join('config/initializers/dymond_site_patch.rb')
  end

  def teardown
    DymondSite.send(:remove_const, :Site)
    ActiveRecord::Base.connection_pool.disconnect!
  end

  def create_sites(domain: false)
    ActiveRecord::Base.connection.create_table(:dymond_site_sites) do |table|
      table.string :host
      table.string :domain if domain
    end
    DymondSite::Site.reset_column_information
  end

  def test_empty_database_can_prepare_then_migrate_and_use_domain_alias
    @reloader.callback.call
    refute DymondSite::Site.table_exists?
    create_sites
    @reloader.callback.call
    site = DymondSite::Site.create!(domain: 'member.example.com')
    assert_equal 'member.example.com', site.host
    assert_equal site, DymondSite::Site.find_by!(domain: 'member.example.com')
    @reloader.callback.call
    assert_equal 'host', DymondSite::Site.attribute_aliases.fetch('domain')
  end

  def test_real_domain_column_is_preserved
    create_sites(domain: true)
    @reloader.callback.call
    site = DymondSite::Site.create!(host: 'host.example.com', domain: 'domain.example.com')
    assert_equal 'host.example.com', site.host
    assert_equal 'domain.example.com', site.domain
    refute DymondSite::Site.attribute_aliases.key?('domain')
  end

  def test_database_creation_can_boot_before_database_exists
    DymondSite::Site.stub(:table_exists?, -> { raise ActiveRecord::NoDatabaseError, 'not created yet' }) do
      @reloader.callback.call
    end
    create_sites
    @reloader.callback.call
    assert_equal 'host', DymondSite::Site.attribute_aliases.fetch('domain')
  end

  def test_unexpected_database_errors_still_surface
    DymondSite::Site.stub(:table_exists?, -> { raise ActiveRecord::StatementInvalid, 'unexpected failure' }) do
      assert_raises(ActiveRecord::StatementInvalid) { @reloader.callback.call }
    end
  end
end
