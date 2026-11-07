# Minimal SQLite/ActiveJob harness for import transactions; full Rails tests live in test/services and test/integration.
require 'logger'
require 'json'
require 'securerandom'
require 'pathname'
require 'active_record'
require "active_support/core_ext"
require 'active_job'
require 'minitest/autorun'
require 'minitest/mock'
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:site_templates) { |t| t.string :key; t.string :name; t.string :description; t.json :settings, default: {}; t.boolean :preset; t.timestamps }
  create_table(:users) { |t| t.string :role }
  create_table(:sites) { |t| t.string :name; t.json :manifest, default: {}; t.integer :tenant_id; t.integer :active_template_id }
  create_table(:pages) { |t| t.integer :site_id; t.string :title; t.string :slug; t.boolean :published; t.integer :position; t.timestamps }
  create_table(:sections) { |t| t.integer :page_id; t.string :kind; t.json :data, default: {}; t.integer :position }
end
module Rails
  def self.root = Pathname.new(File.expand_path("../..", __dir__))
  def self.logger = Logger.new(nil)
end
class User < ActiveRecord::Base; end
class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :test
module DymondSite
  class SiteTemplate < ActiveRecord::Base
    self.table_name = 'site_templates'
  end
  class Site < ActiveRecord::Base
    self.table_name = 'sites'
    belongs_to :tenant, class_name: 'User', optional: true
    belongs_to :active_template, class_name: 'DymondSite::SiteTemplate', optional: true
    has_many :pages, class_name: 'DymondSite::Page'
  end
  class Page < ActiveRecord::Base
    self.table_name = 'pages'
    has_many :sections, class_name: 'DymondSite::Section'
    belongs_to :site, class_name: 'DymondSite::Site'
  end
  class Section < ActiveRecord::Base
    self.table_name = 'sections'
  end
  module Sections
    class Base
      def self.key(value=nil); @key = value if value; @key; end
      def self.template(value); end
      def self.field(*args,**kwargs); end
    end
  end
  module SectionRegistry
    def self.register(klass); end
    def self.find(key) = Struct.new(:schema).new(LightekDesign::CommerceSections.definitions.first['fields'])
  end
end
%w[catalog fonts studio_blocks studio_document studio_context studio_catalog commerce_sections website_designs html_document html_import].each { |name| require Rails.root.join("app/services/lightek_design/#{name}").to_s }
require Rails.root.join('app/services/lightek_settings/website_identity').to_s
require Rails.root.join('app/services/lightek_commerce/industry_starters').to_s
require Rails.root.join('app/jobs/lightek_design/html_import_job').to_s
LightekDesign::Catalog.singleton_class.alias_method(:builtin_designs, :designs)
LightekDesign::Catalog.singleton_class.prepend(LightekDesign::StudioCatalog)
class ImportPersistenceChecks < Minitest::Test
  def setup
    LightekDesign::StudioContext.reset
    @user = User.create!(role: 'admin')
    @site = DymondSite::Site.create!(name: 'Owner shop', tenant: @user)
  end
  def file(name)
    source = File.open(Rails.root.join("test/fixtures/files/website_designs/#{name}.html"))
    source.define_singleton_method(:original_filename) { "#{name}.html" }
    source
  end
  def test_interactive_upload_completes_without_enqueuing_or_a_worker
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.length
    record = LightekDesign::HtmlImport.enqueue!(user: @user, site: @site, html_file: file('lightek_website'), create_page: true)
    assert_equal 'complete', record.settings.dig('html_import', 'status')
    assert_equal queued, ActiveJob::Base.queue_adapter.enqueued_jobs.length
    assert_equal 1, @site.pages.count
    refute @site.pages.first.published?
  end
  def test_enqueue_rejection_keeps_source_available_for_inline_recovery
    record = nil
    LightekDesign::HtmlImportJob.stub(:perform_later, false) do
      record = LightekDesign::HtmlImport.enqueue!(background: true, user: @user, site: @site, html_file: file('lightek_website'), create_page: true)
    end
    assert_equal 'failed', record.settings.dig('html_import', 'status')
    assert_includes record.settings.dig('html_import', 'html'), '<title>'
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal 'complete', record.reload.settings.dig('html_import', 'status')
    assert_equal 1, @site.pages.count
  end
  def test_complete_job_retains_source_and_is_idempotent
    record = LightekDesign::HtmlImport.enqueue!(background: true, user: @user, site: @site, html_file: file('lightek_website'), create_page: true)
    original = record.settings.dig('html_import', 'html')
    LightekDesign::HtmlImportJob.perform_now(record.id)
    meta = record.reload.settings['html_import']
    assert_equal 'complete', meta['status'], meta['error']
    assert_equal original, meta['html']
    assert_equal 1, @site.pages.count
    refute @site.pages.first.published?
    assert_equal 9, @site.pages.first.sections.count
    assert_equal @user.id, LightekDesign::StudioDocument.metadata(DymondSite::SiteTemplate.find(meta['document_id']))['owner_id']
    count = DymondSite::SiteTemplate.count
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal count, DymondSite::SiteTemplate.count
    assert_equal [record.id], LightekDesign::HtmlImport.records_for(user: @user, site: @site).map(&:id)
    assert_empty LightekDesign::HtmlImport.records_for(user: User.create!(role: 'admin'), site: @site)
  end
  def test_revoked_ownership_fails_without_creating_pages
    record = LightekDesign::HtmlImport.enqueue!(background: true, user: @user, site: @site, html_file: file('lightek_website'), create_page: true)
    @site.update!(tenant: nil)
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal 'failed', record.reload.settings.dig('html_import', 'status')
    assert_empty @site.pages
  end
  def test_invalid_selector_rolls_back_and_records_failure
    record = LightekDesign::HtmlImport.enqueue!(background: true, user: @user, site: @site, html_file: file('lightek_website'), create_page: true, product_selector: '[')
    count = DymondSite::SiteTemplate.count
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal 'failed', record.reload.settings.dig('html_import', 'status')
    assert_equal count, DymondSite::SiteTemplate.count
    assert_empty @site.pages
  end
  def test_industry_install_preserves_edited_pages_and_other_industries
    page = LightekCommerce::IndustryStarters.install!(site: @site, industry: 'retail', user: @user)
    assert_equal 6, page.sections.count
    page.update!(title: 'Customer edit', published: true)
    page.sections.first.update!(data: {'heading'=>'Customer hero'})
    second = LightekCommerce::IndustryStarters.install!(site: @site, industry: 'beauty', user: @user)
    refute second.published?
    same = LightekCommerce::IndustryStarters.install!(site: @site, industry: 'retail', user: @user)
    assert_equal page.id, same.id
    assert_equal 'Customer edit', same.title
    assert_equal 'Customer hero', same.sections.first.data['heading']
    assert_equal 2, @site.pages.count
  end
  def test_store_maps_live_products_and_registers_shop_draft
    record = LightekDesign::HtmlImport.enqueue!(background: true, user: @user, site: @site, html_file: file('lightek_store'), create_page: true, product_selector: '#grid')
    LightekDesign::HtmlImportJob.perform_now(record.id)
    meta = record.reload.settings['html_import']
    assert_equal 'complete', meta['status'], meta['error']
    assert_equal meta['page_id'], @site.reload.manifest['lightek_commerce_starter_page_id']
    assert_equal meta['release_key'], @site.manifest['lightek_commerce_design_pages'][meta['page_id'].to_s]
  end
end
