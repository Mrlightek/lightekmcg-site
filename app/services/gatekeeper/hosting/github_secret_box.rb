require "fiddle"
require "base64"
module Gatekeeper
  module Hosting
    class GithubSecretBox
      def self.encrypt(value, public_key)
        library = nil
        %w[libsodium.so.23 libsodium.so libsodium.dylib /opt/local/lib/libsodium.dylib /opt/homebrew/lib/libsodium.dylib].each do |name|
          begin
            library = Fiddle.dlopen(name)
            break
          rescue Fiddle::DLError
            next
          end
        end
        raise GithubClient::Error, "Secret synchronization needs libsodium on this host; the server deployment installs it automatically." unless library
        init = Fiddle::Function.new(library["sodium_init"], [], Fiddle::TYPE_INT)
        raise GithubClient::Error, "Secret encryption initialization failed" if init.call < 0
        key = Base64.strict_decode64(public_key)
        raise GithubClient::Error, "Invalid GitHub encryption public key" unless key.bytesize == 32
        encrypted = "\0".b * (value.bytesize + 48)
        seal = Fiddle::Function.new(library["crypto_box_seal"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        raise GithubClient::Error, "GitHub secret encryption failed" unless seal.call(encrypted, value, value.bytesize, key) == 0
        Base64.strict_encode64(encrypted)
      end
    end
  end
end
