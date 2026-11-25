# frozen_string_literal: true

class ItRemoteSupportRecording < ApplicationRecord
  belongs_to :it_remote_support_session

  def consented?
    customer_consented_at? && technician_consented_at? && !revoked_at?
  end

  def available?
    consented? && payload.present? && expires_at&.future?
  end
end
