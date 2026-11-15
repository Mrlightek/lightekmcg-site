# Two merged migrations originally used 20261115190000. If Studio's seed ran
# first, Rails recorded that version without creating the growth audit tables.
# The Studio seed now has its own version; reconcile either deployed history.
class ReconcileWebsiteGrowthAudits < ActiveRecord::Migration[8.0]
  TABLES = %i[lightek_growth_page_metadata lightek_growth_website_audits lightek_growth_audit_findings lightek_growth_audit_fixes].freeze

  def up
    existing = TABLES.select { |table| table_exists?(table) }
    return if existing.length == TABLES.length
    raise "Website growth audit schema is incomplete; reconcile existing tables before migrating" if existing.any?

    require_relative "20261115190000_add_website_growth_audits"
    AddWebsiteGrowthAudits.new.migrate(:up)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reconciliation preserves existing website audit data"
  end
end
