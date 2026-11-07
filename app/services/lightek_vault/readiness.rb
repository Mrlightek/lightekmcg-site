module LightekVault
  class Readiness
    def self.call
      crypto = Crypto.new
      sample = Secret.order(:id).first
      crypto.decrypt_hash(sample).clear if sample
      {ready: true, message: "Vault access verified for this application process."}
    rescue MasterKey::ConfigurationError, Crypto::DecryptionError => error
      {ready: false, message: error.message}
    end
  end
end
