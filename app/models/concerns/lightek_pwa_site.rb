# frozen_string_literal: true
module LightekPwaSite
  extend ActiveSupport::Concern
  included do
    has_one :pwa_application, class_name: "LightekPwa::Application", foreign_key: :site_id, dependent: :destroy
    has_many :pwa_memberships, class_name: "LightekPwa::Membership", foreign_key: :site_id, dependent: :destroy
    has_many :pwa_admin_events, class_name: "LightekPwa::AdminEvent", foreign_key: :site_id, dependent: :destroy
    after_create :initialize_pwa_application
  end
  private
  def initialize_pwa_application
    # Older migrations can create sites before the PWA configuration table exists.
    return unless LightekPwa::Application.table_exists?
    create_pwa_application!(name: name) unless pwa_application
  end
end
