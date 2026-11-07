namespace :lightek_vault do
  task bootstrap: :environment do
    LightekVault::MasterKey.ensure_available!(create_if_empty: true)
    result = LightekVault::Readiness.call
    abort result.fetch(:message) unless result.fetch(:ready)
    puts "Vault access verified; original encrypted credentials preserved."
  end

  task readiness: :environment do
    puts "=== LIGHTEK VAULT READINESS ==="
    puts "Secrets table: #{LightekVault::Secret.table_exists?}"
    puts "Audit table: #{LightekVault::AuditEvent.table_exists?}"
    puts "Active secrets: #{LightekVault::Secret.active.count}"
    result = LightekVault::Readiness.call
    puts "Crypto: #{result.fetch(:ready) ? 'READY' : 'UNAVAILABLE'}"
    puts result.fetch(:message)
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
