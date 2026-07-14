# frozen_string_literal: true
# ONE-TIME reconcile: record each engine gem migration's ORIGINAL version in
# schema_migrations (marking applied WITHOUT running), so switching engines to
# path-based migrations doesn't re-run already-applied migrations.
#
# Idempotent: ON CONFLICT DO NOTHING. Safe to run more than once.
# Run:  bin/rails runner reconcile_migration_versions.rb
#
# BACK UP YOUR DB FIRST. This writes to schema_migrations directly.

conn    = ActiveRecord::Base.connection
applied = conn.select_values("SELECT version FROM schema_migrations").to_set
gems    = %w[dymond_site dymond_dash dymond_compute dymond_bank dymond_theme]

inserted = []
gems.each do |g|
  dir = begin
    "#{`bundle show #{g}`.strip}/db/migrate"
  rescue
    nil
  end
  next unless dir && Dir.exist?(dir)

  Dir.glob("#{dir}/*.rb").sort.each do |f|
    version = File.basename(f).split("_").first
    next if applied.include?(version)
    conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}') ON CONFLICT DO NOTHING")
    inserted << "#{version}  #{File.basename(f)}"
  end
end

puts "Reconciled #{inserted.size} migration version(s):"
inserted.each { |x| puts "  + #{x}" }
puts "schema_migrations now: #{conn.select_value('SELECT COUNT(*) FROM schema_migrations')} rows"
