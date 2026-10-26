module LightekMail
  class Access
    class Denied < StandardError; end
    def self.authorize!(user)
      raise Denied, "Mail access is not enabled for this account." unless user && (user.role.to_s.in?(%w[admin super_admin employee]) || user.can_access_feature?("mail"))
    end
    def self.accounts(user)
      authorize!(user)
      user.role == "super_admin" ? Account.all : Account.where(user_id: user.id)
    end
    def self.domains(user)
      authorize!(user)
      user.role == "super_admin" ? Domain.all : Domain.where(user_id: user.id)
    end
  end
end
