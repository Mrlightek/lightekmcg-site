module LightekCompliance
  class Access
    def self.authorize!(actor,employer,write: false)
      people = LightekPeople::Access.new(actor: actor,employer: employer)
      people.require_active!
      allowed = people.owner? || (write ? people.membership&.compliance_access == 'administrator' : %w[reviewer administrator].include?(people.membership&.compliance_access))
      raise LightekPeople::Access::Denied, 'Legal and compliance access must be explicitly assigned' unless allowed
    end
  end
end
