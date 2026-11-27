# frozen_string_literal: true

module LightekCommerce
  class ReturnLabel < ApplicationRecord
    self.table_name = 'lightek_commerce_return_labels'

    CARRIERS = {'UPS' => 'ups', 'FedEx' => 'fedex'}.freeze
    MAX_BYTES = 512.kilobytes
    VISIBLE_STATUSES = %w[approved received].freeze

    belongs_to :merchandise_return, class_name: 'LightekCommerce::MerchandiseReturn'

    def self.list_for(returns)
      ids = returns.select { |record| VISIBLE_STATUSES.include?(record.status) }.map(&:id)
      where(merchandise_return_id: ids).select(:id, :merchandise_return_id, :carrier, :tracking_number).index_by(&:merchandise_return_id)
    end

    def tracking_url
      LightekShipping::Quote.carrier_tracking_url(carrier, tracking_number)
    end
  end
end
