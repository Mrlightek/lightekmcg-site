module LightekMail
  class RecipientDirectory
    def self.eligible
      Account.available.joins(:domain).where(enabled: true).where.not(lightek_mail_domains: {verified_at: nil})
    end
    def self.addresses
      mailbox_ids = eligible.where(mailbox_kind: "mailbox").select(:id)
      groups_with_members = GroupMember.where(member_id: mailbox_ids).select(:group_id)
      eligible.where(mailbox_kind: "mailbox").or(eligible.where(mailbox_kind: "group", id: groups_with_members)).order(:address).pluck(:address)
    end
    def self.resolve!(address)
      account = eligible.find_by(address: address)
      raise ArgumentError, "Unknown or unprovisioned envelope recipient." unless account
      return [account.id] if account.mailbox_kind == "mailbox"
      ids = eligible.where(mailbox_kind: "mailbox", user_id: account.user_id, id: account.group_memberships.select(:member_id)).pluck(:id)
      raise ArgumentError, "The distribution group has no enabled member mailboxes." if ids.empty?
      ids
    end
  end
end
