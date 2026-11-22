# frozen_string_literal: true

module LightekIdentity
  module SessionContainment
    module_function

    def revoke!(actor:, employer:, membership_id:)
      access = LightekPeople::Access.new(actor: actor, employer: employer)
      employer.with_lock do
        access.require!(:directory)
        connection = Connection.find_by!(employer: employer)
        membership = LightekPeople::Employment.where(employer: employer).find(membership_id)
        raise ArgumentError, "Choose another team member" if [actor.id, employer.id].include?(membership.worker_id)

        count = Session.where(identity_connection_id: connection.id, user_id: membership.worker_id).delete_all
        LightekPeople::AuditEvent.record!(employer: employer, actor: actor, action: "directory_sso_sessions_revoked", record: membership)
        count
      end
    end
  end
end
