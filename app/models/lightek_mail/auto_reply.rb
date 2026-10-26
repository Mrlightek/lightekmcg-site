module LightekMail
  class AutoReply < ApplicationRecord
    self.table_name = "lightek_mail_auto_replies"
    belongs_to :account, class_name: "LightekMail::Account"
  end
end
