namespace :susu do
  desc "Check Susu production readiness without changing application data"
  task production_readiness: :environment do
    checks = []

    check = lambda do |name, &block|
      begin
        value = block.call
        passed = value != false
        checks << [name, passed, value]
      rescue StandardError => e
        checks << [name, false, "#{e.class}: #{e.message}"]
      end
    end

    check.call("Rails environment") { Rails.env.production? ? "production" : Rails.env }
    check.call("Database") { ActiveRecord::Base.connection.select_value("SELECT 1").to_i == 1 }
    check.call("SusuGroup model") { defined?(SusuGroup) ? "loaded" : false }
    check.call("SusuMembership model") { defined?(SusuMembership) ? "loaded" : false }
    check.call("SusuContribution model") { defined?(SusuContribution) ? "loaded" : false }
    check.call("SusuCycle model") { defined?(SusuCycle) ? "loaded" : false }
    check.call("SusuRound model") { defined?(SusuRound) ? "loaded" : false }
    check.call("SusuCommitment model") { defined?(SusuCommitment) ? "loaded" : false }
    check.call("SusuMatchPreference model") { defined?(SusuMatchPreference) ? "loaded" : false }

    %w[
      susu_groups
      susu_memberships
      susu_contributions
      susu_cycles
      susu_rounds
      susu_commitments
      susu_match_preferences
    ].each do |table|
      check.call("#{table} table") { ActiveRecord::Base.connection.data_source_exists?(table) }
    end

    check.call("Redis") do
      if defined?(Sidekiq)
        Sidekiq.redis { |connection| connection.call("PING") }
      else
        false
      end
    end

    check.call("Susu group routes") do
      helpers = Rails.application.routes.url_helpers
      helpers.respond_to?(:susu_groups_path) ? helpers.susu_groups_path : false
    end

    check.call("Pending migrations") do
      pending = ActiveRecord::MigrationContext
        .new(ActiveRecord::Migrator.migrations_paths)
        .open
        .pending_migrations

      pending.empty? ? "none" : false
    end

    puts
    puts "=== SUSU PRODUCTION READINESS ==="

    checks.each do |name, passed, detail|
      marker = passed ? "PASS" : "FAIL"
      puts format("%-4s  %-30s %s", marker, name, detail.inspect)
    end

    failed = checks.reject { |_name, passed, _detail| passed }

    puts
    puts "Groups:        #{SusuGroup.count if defined?(SusuGroup)}"
    puts "Memberships:   #{SusuMembership.count if defined?(SusuMembership)}"
    puts "Contributions: #{SusuContribution.count if defined?(SusuContribution)}"
    puts "Cycles:        #{SusuCycle.count if defined?(SusuCycle)}"

    puts
    if failed.empty?
      puts "SUSU_READINESS=READY"
    else
      puts "SUSU_READINESS=NOT_READY"
      puts "Failed checks: #{failed.map(&:first).join(', ')}"
      exit 1
    end
  end
end
