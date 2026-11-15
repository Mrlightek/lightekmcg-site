module NevaehOs
  class SpeechJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit=true
    def perform(id) = Speech.generate!(NevaehSpeech.find(id))
  end
end
