module LightekSessions
  class Room < ApplicationRecord
    self.table_name = 'lightek_session_rooms'
    belongs_to :resource, class_name: 'LightekReservations::Resource'
    has_many :members, class_name: 'LightekSessions::Member', dependent: :destroy
    validates :key, :media_name, :starts_at, :ends_at, presence: true
    validates :status, inclusion: {in: %w[scheduled open ended]}
    def self.for_reservation!(reservation)
      raise Access::Denied, 'This experience does not use a Lightek session room.' unless reservation.resource.native_session?
      reservation.resource.with_lock do
        find_or_create_by!(resource: reservation.resource, starts_at: reservation.starts_at, ends_at: reservation.ends_at) do |room|
          room.key = SecureRandom.uuid
          room.media_name = "lightek-#{SecureRandom.hex(20)}"
        end
      end
    end
    def live? = resource.kind == 'live'
    def host?(user) = user && (user.role == 'super_admin' || resource.site.tenant == user)
    def bookings = LightekReservations::Reservation.where(resource: resource, starts_at: starts_at, ends_at: ends_at)
  end
end
