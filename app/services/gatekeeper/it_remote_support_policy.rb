# frozen_string_literal: true

module Gatekeeper
  class ItRemoteSupportPolicy
    class Denied < StandardError; end

    def self.participant!(login:, customer_id:, technician_id:)
      user = login&.user
      raise Denied unless user&.access_active? && login.connect_delegation.blank? && !login.mfa_enrollment_only?

      return :customer if user.id == customer_id
      if user.id == technician_id && ItServices::TechnicianAssignment::ELIGIBLE_ROLES.include?(user.role) &&
          LightekIdentity::Mfa.enabled?(user) && LightekIdentity::Mfa.fresh?(login)
        return :technician
      end

      raise Denied
    end

    def self.case_active!(request, customer_id:, technician_id:)
      unless request.user_id == customer_id && request.technician_id == technician_id && customer_id != technician_id &&
          request.delivery_mode == "remote" && request.status == "in_progress" &&
          request.user&.access_active? && request.technician&.access_active? &&
          ItServices::TechnicianAssignment::ELIGIBLE_ROLES.include?(request.technician.role)
        raise Denied
      end
    end

    def self.browser_bound!(room, login, role)
      bound_id = role == :customer ? room.customer_session_id : room.technician_session_id
      raise Denied if bound_id && bound_id != login.id
    end

    def self.technician_login!(room)
      login = Session.find_by(id: room.technician_session_id)
      raise Denied unless participant!(login: login, customer_id: room.customer_id, technician_id: room.technician_id) == :technician
    end

    def self.live!(room, login, role)
      raise Denied unless room.state == "approved" && room.expires_at.future?
      browser_bound!(room, login, role)
      technician_login!(room)
      customer_login = Session.find_by(id: room.customer_session_id)
      raise Denied unless participant!(login: customer_login, customer_id: room.customer_id, technician_id: room.technician_id) == :customer
    end
  end
end
