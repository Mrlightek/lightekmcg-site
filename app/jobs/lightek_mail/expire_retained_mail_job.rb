module LightekMail
  class ExpireRetainedMailJob < ApplicationJob
    queue_as :default

    def perform
      Retention.expire!
    end
  end
end
