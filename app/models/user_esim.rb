# frozen_string_literal: true

require "ipaddr"
require "base64"
require "rqrcode"

class UserEsim < ApplicationRecord
  UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i
  ICCID = /\A\d{18,22}\z/
  LPA = /\ALPA:1\$[!-~]{1,430}\z/
  CARRIER_STATES = %w[registering enabling enabled disabling disabled data_limit_exceeded setting_standby standby unauthorized_imei].freeze

  belongs_to :user
  self.filter_attributes += [:lpa_activation_code]

  validates :request_key, :sim_card_group_id, format: { with: UUID }
  validates :telnyx_sim_id, format: { with: UUID }, allow_nil: true
  validates :iccid, format: { with: ICCID }, allow_nil: true
  validates :plan_limit_mb, numericality: { only_integer: true, in: 1..2_147_483_647 }
  validate do
    errors.add(:customer_wg_peer_ip, "must be a usable IPv4 host") unless self.class.host_ipv4?(customer_wg_peer_ip)
    if assigned_private_ip && !self.class.host_ipv4?(assigned_private_ip)
      errors.add(:assigned_private_ip, "must be a usable IPv4 host")
    end
  end

  attr_readonly :request_key, :user_id, :sim_card_group_id, :customer_wg_peer_ip, :initial_plan_limit_mb

  def self.host_ipv4?(value)
    return false unless value.is_a?(String) && value.match?(/\A[0-9]+(?:\.[0-9]+){3}\z/)

    address = IPAddr.new(value)
    address.ipv4? && address.to_s == value && !address.loopback? && !address.link_local? &&
      address.to_i > 0 && address.to_i < 0xe0000000
  rescue IPAddr::InvalidAddressError
    false
  end

  def lpa_activation_code=(value)
    unless value.nil? || (value.is_a?(String) && LPA.match?(value))
      raise ArgumentError, "Invalid eSIM activation code"
    end
    self[:lpa_activation_code] = value && activation_lockbox.encrypt(value)
  end

  def lpa_activation_code
    activation_lockbox.decrypt(self[:lpa_activation_code]) if self[:lpa_activation_code]
  end

  def activation_qr_base64
    code = lpa_activation_code
    Base64.strict_encode64(RQRCode::QRCode.new(code, level: :m).as_png(module_px_size: 8).to_s) if code
  end

  def provisioning_authorized?
    return true unless defined?(LightekCommunications::VoiceAddOn)

    add_on = LightekCommunications::VoiceAddOn.find_by(cellular_request_key: request_key)
    return true unless add_on

    user_id == add_on.peer.merchant_id && LightekCommunications::CellularBundle.new(add_on).paid?
  end

  def refresh_status!(carrier)
    value = carrier.dig("status", "value")
    return unless CARRIER_STATES.include?(value)

    visible = if route_installed_at || value.in?(%w[data_limit_exceeded unauthorized_imei])
      value
    elsif activation_requested_at
      "awaiting_device"
    else
      "provisioning"
    end
    update!(carrier_status: value, status: visible)
  end

  private

  def activation_lockbox
    Lockbox.new(key: Lockbox.attribute_key(table: self.class.table_name, attribute: "lpa_activation_code"),
      encode: true)
  end
end
