module LightekSessions
  module Access
    class Denied < StandardError; end
    module_function
    def authorize!(room, user, now: Time.current, joining: false)
      raise Denied, 'Sign in to join this session.' unless user
      raise Denied, 'This session has ended.' if room.status == 'ended' || now >= room.ends_at
      raise Denied, 'This experience uses an external session.' unless room.resource.native_session?
      host = room.host?(user)
      member = room.members.find_by(user: user)
      raise Denied, 'The host has removed you from this session.' if !host && member&.status == 'blocked'
      unless host
        booking = room.bookings.find_by(customer: user) || member&.reservation
        raise Denied, 'A confirmed, paid reservation is required.' unless booking &&
          room.bookings.where(id: booking.id).exists? && booking.access_ready?
      end
      if joining
        raise Denied, 'The room opens 15 minutes before the scheduled start.' if now < room.starts_at - 15.minutes
        raise Denied, 'The host has not opened this room yet.' unless host || room.status == 'open'
        raise Denied, 'The host has locked this room.' if !host && room.locked
        raise Denied, 'Please wait for the host to admit you.' if !host && member&.status != 'admitted'
      end
      true
    end
    def host!(room, user)
      raise Denied, 'Only the site owner or a super admin can control this room.' unless room.host?(user)
    end
    def eligible_member!(room, member)
      authorize!(room, member.user)
      member
    end
    def request!(room, user)
      authorize!(room, user)
      room.with_lock do
        booking = room.bookings.find_by(customer: user)
        member = room.members.find_or_initialize_by(user: user)
        member.reservation ||= booking
        member.last_seen_at = Time.current
        member.status = 'admitted' if room.host?(user)
        member.save!
        member
      end
    end
    def invite!(room, actor, email)
      authorize!(room, actor)
      reservation = room.bookings.find_by!(customer: actor)
      reservation.with_lock do
        user = User.find_by!(email_address: email.to_s.strip.downcase)
        raise Denied, 'This account already has a place in the room.' if room.members.exists?(user: user) || room.bookings.exists?(customer: user)
        raise Denied, 'All places on this reservation are assigned.' if room.members.where(reservation: reservation).where.not(user: actor).count >= reservation.quantity - 1
        room.members.create!(user: user, reservation: reservation)
      end
    end
  end
end
