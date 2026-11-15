# Additional real-schema support shared by CRM and intake acceptance suites.
require 'active_job'
require 'nokogiri'
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)
if ActiveRecord::Base.connection.adapter_name == 'SQLite'
  ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
end
require ROOT.join('db/migrate/20261115120000_add_lifecycle_controls')
AddLifecycleControls.new.migrate(:up)
User.reset_column_information
require ROOT.join('app/models/lightek_people/lifecycle_case')
require ROOT.join('app/services/lightek_people/lifecycle_access')
ActiveRecord::Schema.define do
  create_table(:website_template_inquiries) { |t| t.references :site; t.string :template_key; t.string :section_key; t.json :fields; t.timestamps }
  create_table(:dymond_site_pages) { |t| t.references :site; t.boolean :published, default: false }
  create_table(:dymond_site_sections) { |t| t.references :page; t.json :data }
end
module DymondSite
  class Site
    has_many :pages, class_name: 'DymondSite::Page'
  end
  class Page < ApplicationRecord
    self.table_name = 'dymond_site_pages'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :sections, class_name: 'DymondSite::Section'
  end
  class Section < ApplicationRecord
    self.table_name = 'dymond_site_sections'
    belongs_to :page, class_name: 'DymondSite::Page'
  end
end
require ROOT.join('db/migrate/20261115021000_add_sales_intake_and_tasks')
AddSalesIntakeAndTasks.new.migrate(:up)
%w[intake_rule intake_entry task].each { |file| require ROOT.join("app/models/lightek_sales/#{file}") }
%w[tasks intake task_calendar].each { |file| require ROOT.join("app/services/lightek_sales/#{file}") }
require ROOT.join('app/services/lightek_design/starter_library')
module LightekDesign::StarterLibrary
  def self.directory = ROOT.join('config/lightek_designs/starters')
end
require ROOT.join('app/jobs/application_job')
%w[intake_job intake_sweep_job].each { |file| require ROOT.join("app/jobs/lightek_sales/#{file}") }
require ROOT.join('app/models/website_template_inquiry')
# Package account storage/limits are a boundary fixture. The worker calls the
# production authorization/reservation interface; tests observe its accounting.
module LightekAgency
  class PackagePolicy
    class Denied < StandardError; end
    class << self
      attr_accessor :allowed, :reserved, :released
      def authorize!(*args)
        raise Denied, 'Commerce disabled' unless allowed
        true
      end
      def reserve_write!(**)
        raise Denied, 'Commerce disabled' unless allowed
        self.reserved += 1
        [reserved]
      end
      def release_write!(ids) = self.released += ids.size
    end
  end
end

require_relative 'sales_quote_support'
