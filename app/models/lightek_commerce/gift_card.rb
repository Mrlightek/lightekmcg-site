# frozen_string_literal: true

require 'digest'

module LightekCommerce
  class GiftCard < ApplicationRecord
    self.table_name = 'lightek_commerce_gift_cards'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :purchase_order, class_name: 'LightekCommerce::Order'
    has_many :redemptions, class_name: 'LightekCommerce::GiftRedemption', dependent: :restrict_with_error

    def self.digest(code)
      normalized = code.to_s.upcase.delete('- ').strip
      return unless normalized.match?(/\A[0-9A-F]{32}\z/)

      Digest::SHA256.hexdigest(normalized)
    end

    def self.encryptor
      cipher = 'aes-256-gcm'
      key = Rails.application.key_generator.generate_key('commerce gift card code v1', ActiveSupport::MessageEncryptor.key_len(cipher))
      ActiveSupport::MessageEncryptor.new(key, cipher: cipher)
    end

    def self.issue!(order, livemode:)
      raise ArgumentError, 'Gift card funding is unverified' unless order.gift_card_purchase? && order.paid_at? && order.status == 'fulfilled'

      find_or_create_by!(purchase_order: order) do |card|
        code = SecureRandom.hex(16).upcase
        card.assign_attributes(site: order.site, store_scope: order.gift_scope, livemode: livemode, face_cents: order.subtotal_cents, available_cents: order.subtotal_cents,
          code_digest: digest(code), encrypted_code: encryptor.encrypt_and_sign(code))
      end
    end

    def display_code
      self.class.encryptor.decrypt_and_verify(encrypted_code).scan(/.{4}/).join('-')
    end

    def usable? = blocked_at.nil? && disputed_at.nil? && revoked_at.nil?
  end
end
