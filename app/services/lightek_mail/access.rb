module LightekMail
  class Access
    class Denied < StandardError; end
    def self.authorize!(user)
      raise Denied, "Mail access is not enabled for this account." unless user && (user.role.to_s.in?(%w[admin super_admin employee]) || user.can_access_feature?("mail"))
    end
    def self.accounts(user)
      authorize!(user)
      user.role == "super_admin" ? Account.mailboxes : Account.mailboxes.where(user_id: user.id)
    end
    def self.groups(user)
      authorize!(user)
      user.role == "super_admin" ? Account.groups : Account.groups.where(user_id: user.id)
    end
    def self.domains(user)
      authorize!(user)
      user.role == "super_admin" ? Domain.all : Domain.where(user_id: user.id)
    end
  end
end
