module LightekMail
  class RetentionRule < ApplicationRecord
    self.table_name = "lightek_mail_retention_rules"

    belongs_to :account, class_name: "LightekMail::Account"

    validates :days, numericality: {only_integer: true, in: 1..36_500}

    def cutoff(now = Time.current)
      now - days.days
    end
  end
end
