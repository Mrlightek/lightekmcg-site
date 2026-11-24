# frozen_string_literal: true

class ProvisionEsimJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true

  retry_on Telnyx::WirelessClient::Retryable, Telnyx::CellularHub::Error, wait: :polynomially_longer, attempts: 9
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    Telnyx::ProvisionEsimService.new(UserEsim.find(id)).provision!
  end
end
