# frozen_string_literal: true

module LightekTeam
  class Workspace
    def self.employers_for(actor)
      scope = LightekPeople::Access.employers_for(actor).where(access_suspended_at: nil)
      memberships = LightekPeople::Employment.active.where(worker: actor).select(:employer_id)
      scope.where(id: memberships).or(scope.where(id: actor.id))
    end

    def initialize(actor:, employer:)
      @actor = actor
      @employer = employer
      authorize!
    end

    def channels
      authorize!
      scope = Channel.where(employer: @employer)
      memberships = Membership.where(user: @actor).select(:channel_id)
      scope.where(private_channel: false).or(scope.where(id: memberships))
    end

    def roster
      memberships = LightekPeople::Employment.active.where(employer: @employer).select(:worker_id)
      active = User.where(access_suspended_at: nil)
      active.where(id: @employer.id).or(active.where(id: memberships))
    end

    def create!(attributes)
      authorize!
      Channel.transaction do
        channel = Channel.create!(employer: @employer, creator: @actor, **attributes.symbolize_keys)
        channel.memberships.create!(user: @actor) if channel.private_channel?
        channel
      end
    end

    def owner_controls?(channel)
      channel.private_channel? && (channel.creator_id == @actor.id || @employer.id == @actor.id)
    end

    def change_member!(channel_id, user_id, operation:)
      channel = channels.find(channel_id)
      channel.with_lock do
        channels.find(channel.id)
        raise LightekPeople::Access::Denied unless owner_controls?(channel)

        case operation
        when :add
          user = roster.find(user_id)
          channel.memberships.find_or_create_by!(user: user)
        when :remove
          membership = channel.memberships.find_by!(user_id: user_id)
          raise ArgumentError, 'The channel creator retains access while they belong to the organization.' if membership.user_id == channel.creator_id
          membership.destroy!
        end
      end
    end

    def post!(channel_id, attributes)
      channel = channels.find(channel_id)
      channel.with_lock do
        channels.find(channel.id)
        request_key = attributes['request_key']
        body = attributes['body'].to_s.strip
        reply = channel.messages.find(attributes['reply_to_id']) if attributes['reply_to_id'].present?
        messages = channel.messages.where(author: @actor)
        existing = messages.find_by(request_key: request_key)
        if existing
          raise ArgumentError, 'This message was already sent. Refresh to start a new message.' unless existing.body == body && existing.reply_to_id == reply&.id
          return existing
        end

        messages.create!(body: body, request_key: request_key, reply_to: reply)
      end
    end

    private

    def authorize!
      raise LightekPeople::Access::Denied unless LightekPeople::LifecycleAccess.active?(@employer.reload)

      LightekPeople::Access.new(actor: @actor, employer: @employer).require_active!
    end
  end
end
