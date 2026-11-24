module LightekMail
  class MatterReviewer < ApplicationRecord
    self.table_name = "lightek_mail_matter_reviewers"

    belongs_to :matter, class_name: "LightekMail::Matter", inverse_of: :reviewers
    belongs_to :user
  end
end
