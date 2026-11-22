# frozen_string_literal: true

module LightekTeam
  class SharedChannels
    def initialize(workspace:, organization:, actor:)
      @workspace = workspace
      @organization = organization
      @actor = actor
    end

    def incoming
      return Partnership.none unless owner?

      available_invitations.open_invitations
    end

    def invite!(attributes)
      require_owner!
      email = attributes.fetch('partner_email', '').to_s.strip.downcase
      partner = eligible_organizations.where.not(id: @organization.id).find_by(email_address: email)
      raise ArgumentError, 'Enter the account email of another active Lightek organization owner.' unless partner

      Channel.transaction do
        channel = @workspace.create!(attributes.slice('name', 'description').merge('private_channel' => true))
        channel.create_partnership!(partner: partner)
        channel
      end
    end

    def accept!(id)
      require_owner!
      channel = available_invitations.find(id).channel
      channel.with_lock do
        require_owner!
        record = available_invitations.find(id)
        unless record.connected?
          record.memberships.create!(user: @actor)
          record.update!(accepted_at: Time.current)
        end
      end
      channel
    end

    def disconnect!(channel)
      require_owner!
      channel.with_lock do
        record = channel.partnership
        raise ActiveRecord::RecordNotFound unless record && [channel.employer_id, record.partner_id].include?(@organization.id)

        record.update!(closed_at: Time.current) unless record.closed_at?
      end
    end

    private

    def available_invitations
      Partnership.where(partner: @organization, closed_at: nil, channel: Channel.where(employer: eligible_organizations))
    end

    def eligible_organizations
      User.where(role: LightekPeople::Access::BUSINESS_ROLES, access_suspended_at: nil)
    end

    def owner?
      @organization.id == @actor.id && eligible_organizations.exists?(id: @actor.id)
    end

    def require_owner!
      raise LightekPeople::Access::Denied unless owner?
    end
  end
end
