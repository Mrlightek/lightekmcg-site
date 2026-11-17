require Rails.root.join('lib/middleware/pwa_migration_guard')
Rails.application.config.middleware.insert_before 0, Lightek::PwaMigrationGuard
