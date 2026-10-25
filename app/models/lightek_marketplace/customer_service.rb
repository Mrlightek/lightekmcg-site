# frozen_string_literal: true
module LightekMarketplace
  class CustomerService < ActiveRecord::Base
    self.table_name = "lightek_marketplace_customer_services"
    scope :available, -> { where(active: true).order(:name, :id) }
    validates :name, presence: true, length: {maximum: 100}
    validates :description, presence: true, length: {maximum: 600}
    validates :feature_key, presence: true, length: {maximum: 100}
    validates :customer_path, presence: true, length: {maximum: 200},
      format: {with: /\A\/(?!\/)[a-zA-Z0-9_\/-]*\z/, message: "must be a local application path, such as /studio"}
    validate :customer_feature_exists
    validate :ready_application_route_exists
    def ready? = active? && errors.empty?
    private
    def customer_feature_exists
      key = feature_key.to_s
      if ProductForm.protected_features.include?(key) || key.start_with?("employee_", "dashboard_")
        errors.add(:feature_key, "is an administration feature and cannot be sold as customer access")
      elsif !defined?(Marlon::Feature) || !Marlon::Feature.exists?(key: key, active: true)
        errors.add(:feature_key, "must identify an active application feature")
      end
    end
    def ready_application_route_exists
      return unless active? && customer_path.present? && errors[:customer_path].empty?
      Rails.application.routes.recognize_path(customer_path, method: :get)
    rescue ActionController::RoutingError, ActionController::UrlGenerationError
      errors.add(:customer_path, "does not match an application page. Keep this connection in draft until it is available.")
    end
  end
end
