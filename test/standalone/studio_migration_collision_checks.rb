require_relative "website_audit_checks"
require Rails.root.join("db/migrate/20261115190002_reconcile_website_growth_audits")
class StudioMigrationCollisionTest < WebsiteAuditChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  WebsiteAuditChecks.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def test_merged_migrations_have_unique_versions
    migrations = ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate")).migrations
    versions = migrations.map(&:version)
    assert_equal versions.uniq.length, versions.length
    assert_includes versions, 20261115190001
    assert_includes versions, 20261115190002
    assert_includes versions, 20261115210000
  end

  def test_already_installed_growth_schema_and_data_are_preserved
    report = audit
    2.times { ReconcileWebsiteGrowthAudits.new.migrate(:up) }
    assert_equal report.id, LightekGrowth::WebsiteAudit.find(report.id).id
    assert report.reload.findings.any?
  end

  def test_studio_only_old_version_recovers_missing_growth_schema
    ReconcileWebsiteGrowthAudits::TABLES.reverse_each { |table| ActiveRecord::Base.connection.drop_table(table) }
    ReconcileWebsiteGrowthAudits.new.migrate(:up)
    ReconcileWebsiteGrowthAudits::TABLES.each { |table| assert ActiveRecord::Base.connection.table_exists?(table) }
    assert_equal "completed", audit.status
    ReconcileWebsiteGrowthAudits.new.migrate(:up)
    assert_equal 1, LightekGrowth::WebsiteAudit.count
  end
end
