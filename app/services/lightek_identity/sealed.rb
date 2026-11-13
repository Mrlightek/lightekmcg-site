require 'ostruct'
module LightekIdentity
  module Sealed
    def self.pack(data, context:)
      LightekVault::Crypto.new.encrypt_hash({'context'=>context, 'data'=>data}).stringify_keys
    end
    def self.open(box, context:)
      value = LightekVault::Crypto.new.decrypt_hash(OpenStruct.new(box))
      raise SecurityError, 'Encrypted record context mismatch' unless value['context'] == context
      value.fetch('data')
    end
  end
end
