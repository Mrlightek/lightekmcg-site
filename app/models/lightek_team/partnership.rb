# frozen_string_literal: true

module LightekTeam
  class Partnership < ApplicationRecord
    self.table_name = 'lightek_team_partnerships'

    belongs_to :channel, class_name: 'LightekTeam::Channel'
    belongs_to :partner, class_name: 'User'
    has_many :memberships, class_name: 'LightekTeam::PartnerMembership', dependent: :restrict_with_error

    scope :open_invitations, -> { where(accepted_at: nil, closed_at: nil) }
    scope :connected, -> { where(closed_at: nil).where.not(accepted_at: nil) }

    def connected?
      accepted_at? && !closed_at?
    end

    def status_label
      return 'Disconnected' if closed_at?

      accepted_at? ? 'Connected' : 'Invitation pending'
    end
  end
end
