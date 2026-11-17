require Rails.root.join('lib/middleware/pwa_member_guard')
Rails.application.config.middleware.use Lightek::PwaMemberGuard
