module LightekMail
  class Matter < ApplicationRecord
    self.table_name = "lightek_mail_matters"

    belongs_to :employer, class_name: "User"
    has_many :holds, class_name: "LightekMail::MatterHold", inverse_of: :matter
    has_many :reviewers, class_name: "LightekMail::MatterReviewer", inverse_of: :matter

    validates :name, presence: true, length: {maximum: 100}
  end
end
