require "base64"
require "openssl"
require "fileutils"
require "pathname"
require "tempfile"

module LightekVault
  # The wrapping key is external to the database and is never a Vault secret.
  class MasterKey
    class ConfigurationError < StandardError; end

    def self.resolve!(create_if_empty: false)
      value = ENV["LIGHTEK_VAULT_MASTER_KEY"].presence
      return validate!(value) if value
      value = credentials_key
      return validate!(value) if value.present?
      path = key_path
      return read!(path) if path.file?
      value = environment_file_key
      return validate!(value) if value.present?
      if create_if_empty && LightekVault::Secret.table_exists? && !LightekVault::Secret.exists?
        return create_key!(path)
      end
      raise ConfigurationError, "This process cannot find the Vault master key. Restore the original key through Vault access repair; existing credentials will be preserved."
    end

    def self.ensure_available!(create_if_empty: false)
      value = resolve!(create_if_empty: create_if_empty)
      restore!(value)
      value
    end

    def self.key_path
      Pathname.new(ENV["LIGHTEK_VAULT_MASTER_KEY_FILE"].presence || Rails.root.join("storage/lightek-vault/master.key").to_s)
    end

    def self.validate!(value)
      raw = Base64.strict_decode64(value.to_s) rescue nil
      raise ConfigurationError, "Vault master key is malformed; it must be Base64 for exactly 32 bytes." unless raw&.bytesize == 32
      value.to_s
    ensure
      raw&.clear
    end

    def self.read!(path)
      raise ConfigurationError, "Vault key file must have private permissions (0600)." unless path.stat.mode & 0o077 == 0
      validate!(path.read.strip)
    rescue Errno::EACCES
      raise ConfigurationError, "This application process cannot read its Vault key file."
    end

    def self.create_key!(path)
      FileUtils.mkdir_p(path.dirname, mode: 0o700)
      # A common lock serializes first use across Passenger and background workers.
      File.open(path.dirname.join("bootstrap.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        return read!(path) if path.file?
        raise ConfigurationError, "An existing Vault requires its original master key; no replacement was generated." if LightekVault::Secret.exists?
        value = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
        write_new!(path, value)
        value
      end
    rescue Errno::EACCES, Errno::EROFS
      raise ConfigurationError, "The application cannot create its persistent Vault key file. Check storage directory permissions."
    end

    def self.write_new!(path, value)
      Tempfile.create("vault-key", path.dirname, mode: 0o600) do |file|
        file.chmod(0o600)
        file.write(value + "\n")
        file.flush
        file.fsync
        File.link(file.path, path) # exclusive creation, no replacing an existing key
      end
    end

    def self.credentials_key
      return unless Rails.respond_to?(:application) && Rails.application
      Rails.application.credentials.dig(:lightek_vault, :master_key).presence || Rails.application.credentials[:lightek_vault_master_key]
    rescue ActiveSupport::EncryptedFile::MissingKeyError, ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def self.environment_file_key
      paths = [ENV["LIGHTEK_RUNTIME_ENV_FILE"].presence, "/etc/lightek/#{Rails.root.basename}.env"].compact.uniq
      paths.each do |name|
        path = Pathname.new(name)
        next unless path.file? && path.readable?
        # Read just the literal key; never source a shell file inside a web process.
        line = path.each_line.find { |row| row.match?(/\A(?:export\s+)?LIGHTEK_VAULT_MASTER_KEY\s*=/) }
        next unless line
        value = line.split("=", 2).last.strip
        if value.start_with?("'", '"')
          quote = value[0]
          raise ConfigurationError, "Malformed Vault key in the runtime environment file." unless value.end_with?(quote)
          value = value[1...-1]
        end
        return value
      end
      nil
    end

    def self.restore!(value)
      value = validate!(value.to_s.strip)
      # Successful authenticated decryption is required before replacing a wrong key file.
      secret = LightekVault::Secret.order(:id).first
      Crypto.new(master_key: value).decrypt_hash(secret).clear if secret
      path = key_path
      previous = nil
      FileUtils.mkdir_p(path.dirname, mode: 0o700)
      File.open(path.dirname.join("bootstrap.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        if path.file?
          previous = path.read.strip
          if previous == value
            path.chmod(0o600)
          else
            raise ConfigurationError, "A different persistent key exists and there is no ciphertext to verify the replacement." unless secret
            backup = path.dirname.join(".vault-key-recovery-#{OpenSSL::Random.random_bytes(8).unpack1('H*')}")
            File.open(backup, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(previous + "\n"); file.flush; file.fsync }
            Tempfile.create("vault-key", path.dirname) do |file|
              file.chmod(0o600)
              file.write(value + "\n"); file.flush; file.fsync
              File.rename(file.path, path)
            end
          end
        else
          write_new!(path, value)
        end
      end
      true
    rescue Errno::EACCES, Errno::EROFS
      raise ConfigurationError, "The application cannot persist the restored Vault key. Check storage directory permissions."
    ensure
      previous&.clear
    end
  end
end
