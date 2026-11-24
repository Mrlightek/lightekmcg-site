# frozen_string_literal: true

class ItRemoteSupportFileScanJob < ApplicationJob
  queue_as :default

  def perform(id)
    transfer = ItRemoteSupportTransfer.find_by(id: id)
    ItServices::RemoteSupportFiles.scan!(transfer) if transfer
  end
end
