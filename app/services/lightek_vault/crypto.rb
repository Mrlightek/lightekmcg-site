require "openssl"
require "base64"
require "json"

module LightekVault
  class Crypto
    class ConfigurationError < StandardError; end
    class DecryptionError < StandardError; end
    CIPHER = "aes-256-gcm".freeze

    def initialize(master_key: ENV["LIGHTEK_VAULT_MASTER_KEY"], key_version: ENV.fetch("LIGHTEK_VAULT_KEY_VERSION", "1"))
      @master_key = decode_master_key(master_key)
      @key_version = Integer(key_version)
    end

    attr_reader :key_version

    def encrypt_hash(payload)
      data_key = OpenSSL::Random.random_bytes(32)
      payload_json = JSON.generate(payload.to_h)
      payload_box = encrypt_bytes(payload_json, data_key)
      key_box = encrypt_bytes(data_key, @master_key)
      {
        ciphertext: payload_box.fetch(:ciphertext),
        encrypted_data_key: key_box.fetch(:ciphertext),
        payload_iv: payload_box.fetch(:iv),
        payload_tag: payload_box.fetch(:tag),
        key_iv: key_box.fetch(:iv),
        key_tag: key_box.fetch(:tag),
        key_version: key_version
      }
    ensure
      data_key&.clear if data_key.respond_to?(:clear)
      payload_json&.clear if payload_json.respond_to?(:clear)
    end

    def decrypt_hash(secret)
      data_key = decrypt_bytes(ciphertext: secret.encrypted_data_key, iv: secret.key_iv, tag: secret.key_tag, key: @master_key)
      plaintext = decrypt_bytes(ciphertext: secret.ciphertext, iv: secret.payload_iv, tag: secret.payload_tag, key: data_key)
      JSON.parse(plaintext)
    rescue OpenSSL::Cipher::CipherError, JSON::ParserError => e
      raise DecryptionError, "Vault decryption failed: #{e.class}"
    ensure
      data_key&.clear if data_key.respond_to?(:clear)
      plaintext&.clear if plaintext.respond_to?(:clear)
    end

    private

    def decode_master_key(value)
      raise ConfigurationError, "LIGHTEK_VAULT_MASTER_KEY is missing" if value.blank?
      raw = Base64.strict_decode64(value) rescue nil
      unless raw&.bytesize == 32
        raise ConfigurationError, "LIGHTEK_VAULT_MASTER_KEY must be Base64 for exactly 32 bytes"
      end
      raw
    end

    def encrypt_bytes(plaintext, key)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.encrypt
      cipher.key = key
      iv = OpenSSL::Random.random_bytes(12)
      cipher.iv = iv
      cipher.auth_data = ""
      encrypted = cipher.update(plaintext) + cipher.final
      { ciphertext: Base64.strict_encode64(encrypted), iv: Base64.strict_encode64(iv), tag: Base64.strict_encode64(cipher.auth_tag) }
    end

    def decrypt_bytes(ciphertext:, iv:, tag:, key:)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.decrypt
      cipher.key = key
      cipher.iv = Base64.strict_decode64(iv)
      cipher.auth_tag = Base64.strict_decode64(tag)
      cipher.auth_data = ""
      cipher.update(Base64.strict_decode64(ciphertext)) + cipher.final
    end
  end
end
