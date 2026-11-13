module LightekMail
  class GroupMember < ApplicationRecord
    self.table_name = "lightek_mail_group_members"
    belongs_to :group, class_name: "LightekMail::Account"
    belongs_to :member, class_name: "LightekMail::Account"
    validates :member_id, uniqueness: {scope: :group_id}
    validate do
      errors.add(:group, "must be a distribution group") unless group&.mailbox_kind == "group" && group.deleted_at.nil?
      errors.add(:member, "must be an available mailbox owned by the same customer") unless member && member.mailbox_kind == "mailbox" && member.deleted_at.nil? && member.user_id == group&.user_id
    end
  end
end
