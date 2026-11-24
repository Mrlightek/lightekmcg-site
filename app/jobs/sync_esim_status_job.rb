# frozen_string_literal: true

class SyncEsimStatusJob < ApplicationJob
  class TransitionPending < StandardError; end

  queue_as :default
  self.enqueue_after_transaction_commit = true
  retry_on TransitionPending, wait: 30.seconds, attempts: 20
  retry_on Telnyx::WirelessClient::Retryable, wait: :polynomially_longer, attempts: 8
  discard_on ActiveRecord::RecordNotFound

  def perform(id, event_id = nil)
    esim = UserEsim.find(id)
    pending = esim.with_lock do
      return unless esim.telnyx_sim_id?
      return if event_id && TelnyxEsimEvent.exists?(event_id: event_id)

      card = Telnyx::WirelessClient.new.sim(esim.telnyx_sim_id)
      if card["id"] != esim.telnyx_sim_id || card["sim_card_group_id"] != esim.sim_card_group_id
        raise Telnyx::WirelessClient::Error, "Telnyx returned an unexpected SIM identity"
      end
      esim.refresh_status!(card)
      transitioning = card["actions_in_progress"] || esim.carrier_status.in?(%w[registering enabling disabling setting_standby])
      TelnyxEsimEvent.create!(event_id: event_id, user_esim: esim) if event_id && !transitioning
      transitioning
    end
    raise TransitionPending if pending
  end
end
