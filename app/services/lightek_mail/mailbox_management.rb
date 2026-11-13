module LightekMail
  class MailboxManagement
    def self.create!(user:, domain:, local_part:, display_name:)
      domain = Access.domains(user).find(domain.id)
      Account.create!(user_id: domain.user_id, domain: domain, address: "#{local_part}@#{domain.name}", display_name: display_name, enabled: true)
    end
    def self.save_group!(domain:, local_part:, display_name:, member_ids:, group: nil)
      ids = Array(member_ids).reject(&:blank?).map { |id| Integer(id.to_s, 10) }.uniq
      raise ArgumentError, "Choose between 1 and 100 member mailboxes." unless ids.size.between?(1, 100)
      Account.transaction do
        members = Account.mailboxes.where(user_id: domain.user_id, id: ids).lock.to_a
        raise ArgumentError, "All group members must belong to this domain’s customer." unless members.size == ids.size
        group ||= Account.new(user_id: domain.user_id, domain: domain, mailbox_kind: "group", enabled: true)
        group.lock! if group.persisted?
        raise ArgumentError, "This is not an available distribution group." unless group.mailbox_kind == "group" && group.deleted_at.nil? && group.domain_id == domain.id
        group.update!(address: "#{local_part}@#{domain.name}", display_name: display_name, enabled: true)
        group.group_memberships.where.not(member_id: ids).destroy_all
        members.each { |member| group.group_memberships.find_or_create_by!(member: member) }
        group
      end
    end
  end
end
