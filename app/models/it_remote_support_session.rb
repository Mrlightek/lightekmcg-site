# frozen_string_literal: true

class ItRemoteSupportSession < ApplicationRecord
  belongs_to :it_service_request
  belongs_to :customer, class_name: "User"
  belongs_to :technician, class_name: "User"

  has_many :transfers, class_name: "ItRemoteSupportTransfer", dependent: :restrict_with_error

  scope :open, -> { where(state: %w[requested approved]) }

  def self.available?
    table_exists? && defined?(ItServiceRequest) && ItServiceRequest.table_exists? &&
      ItServiceRequest.column_names.include?("technician_id") && defined?(ItServiceEvent) && ItServiceEvent.table_exists?
  end
end
