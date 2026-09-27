namespace :lightek_vault do
  task readiness: :environment do
    key = ENV["LIGHTEK_VAULT_MASTER_KEY"]
    puts "=== LIGHTEK VAULT READINESS ==="
    puts "Master key:      #{key.present? ? "PRESENT" : "MISSING"}"
    puts "Key version:     #{ENV.fetch("LIGHTEK_VAULT_KEY_VERSION", "1")}"
    puts "Secrets table:   #{LightekVault::Secret.table_exists?}"
    puts "Audit table:     #{LightekVault::AuditEvent.table_exists?}"
    puts "Active secrets:  #{LightekVault::Secret.active.count}"
    puts "Expiring soon:   #{LightekVault::Secret.expiring_soon.count}"
    begin
      key.present? ? LightekVault::Crypto.new : nil
      puts "Crypto:          #{key.present? ? "READY" : "NOT CONFIGURED"}"
    rescue StandardError => e
      puts "Crypto:          ERROR #{e.message}"
    end
  end

  task learn: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-LIGHTEK-VAULT-BOUNDARY",
      title: "Gatekeeper consumes secrets through Lightek Vault handles",
      capability: "secret_management",
      symptom: "A provider or system integration requires credentials, keys, certificates, or signing material.",
      cause: "Long-lived secrets distributed through configuration, provider records, UI state, or logs create uncontrolled secret exposure.",
      remediation: "Store secret material in Lightek Vault using per-secret data encryption keys wrapped by an external master key. Provider records reference Vault secret slugs. Gatekeeper checks out secrets only for an authorized consumer and purpose. Never log or redisplay plaintext values.",
      verification: "Confirm encryption/decryption round-trip, denied unauthorized checkout, audited authorized checkout, no plaintext rendering, and no master key in PostgreSQL.",
      metadata: { component: "lightek_vault", auto_executable: false, encryption: "AES-256-GCM envelope encryption", plaintext_logging_allowed: false }
    )
    puts "Recorded GK-LESSON-LIGHTEK-VAULT-BOUNDARY as KB article #{article.id}"
  end
end
