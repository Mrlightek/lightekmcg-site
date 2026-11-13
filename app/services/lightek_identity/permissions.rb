module LightekIdentity
  class Permissions
    def self.ids(actor, type, permission)
      return [] unless actor && ResourceGrant.table_exists? && %w[GatekeeperNode GatekeeperHostedApplication].include?(type)
      memberships = LightekPeople::Employment.active.where(worker_id: actor.id)
      allowed = permission == 'read' ? %w[read manage] : [permission]
      memberships.flat_map do |member|
        base = ResourceGrant.where(employer_id: member.employer_id, resource_type: type, permission: allowed)
        ids = base.where(subject_type: 'LightekPeople::Employment',subject_id: member.id).pluck(:resource_id)
        if LightekPeople::Department.exists?(id: member.department_id,employer_id: member.employer_id,active: true)
          ids += base.where(subject_type: 'LightekPeople::Department',subject_id: member.department_id).pluck(:resource_id)
        end
        scope = type.constantize.where(id: ids, owner_id: member.employer_id)
        scope = scope.where(owner_type: 'User') if type == 'GatekeeperNode'
        scope.pluck(:id)
      end.uniq
    end
    def self.application!(actor, app, permission)
      return true if Gatekeeper::Hosting::Access.super_admin?(actor) || Gatekeeper::Hosting::Access.manages?(actor, app.owner)
      return true if ids(actor,'GatekeeperHostedApplication',permission).include?(app.id)
      raise Gatekeeper::Hosting::Access::Denied, 'Application access has not been granted'
    end
  end
end
