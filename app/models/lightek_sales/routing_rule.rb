# frozen_string_literal: true
module LightekSales
  class RoutingRule < ApplicationRecord
    self.table_name = 'lightek_sales_routing_rules'
    include SalesSiteRecord
    before_validation { self.source = source.to_s.strip.downcase }
    validates :owner, presence: true
    validates :source, presence: true, length: {maximum: 80}, uniqueness: {scope: :site_id}
  end
end
