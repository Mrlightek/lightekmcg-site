# Adds the production session/presence schema to the existing community fixture.
# Vault remains a private-engine boundary; its fixture stores no real credentials.
def migrate_session_fixture(name)
  path=File.join(ROOT,"db/migrate/#{name}.rb")
  source=File.read(path)
  source=source.gsub('Migration[8.0]',"Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
  eval(source,TOPLEVEL_BINDING,path)
  source.match(/class (\w+) </)[1].constantize.new.migrate(:up)
end
%w[20261028101500_create_lightek_commerce_products 20261028113000_create_lightek_commerce_orders
   20261108190000_create_lightek_resort_reservations 20261109000000_create_lightek_session_rooms
   20261109001000_create_lightek_live_viewers 20261109002000_create_lightek_audience_leases
   20261109003000_add_session_presentation].each { |name| migrate_session_fixture(name) }
ActiveRecord::Schema.define do
  add_column :users,:first_name,:string unless column_exists?(:users,:first_name)
  create_table(:lightek_vault_secrets) { |t| t.string :slug; t.string :status; t.json :payload; t.datetime :expires_at }
end
module LightekVault
  class Secret < ApplicationRecord;end
  class Service
    class AccessDenied < StandardError;end
    def self.checkout!(slug:, **) = Secret.find_by!(slug:slug,status:'active').payload.deep_dup
    def self.store!(slug:,payload:,**) = Secret.find_or_initialize_by(slug:slug).tap { |s| s.update!(status:'active',payload:payload) }
  end
end
%w[app/models/lightek_reservations/resource app/models/lightek_sessions/room app/models/lightek_sessions/member
   app/models/studio_live_viewer app/services/studio/live/audience].each { |file| require File.join(ROOT,file) }
