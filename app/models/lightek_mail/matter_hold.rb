module LightekMail
  class MatterHold < ApplicationRecord
    self.table_name = "lightek_mail_matter_holds"

    belongs_to :matter, class_name: "LightekMail::Matter", inverse_of: :holds
    belongs_to :account, class_name: "LightekMail::Account"

    scope :active, -> { where(released_at: nil) }
  end
end
