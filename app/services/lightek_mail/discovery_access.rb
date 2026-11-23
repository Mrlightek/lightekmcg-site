module LightekMail
  class DiscoveryAccess
    attr_reader :actor

    def initialize(actor)
      @actor = actor
      raise LightekPeople::Access::Denied unless actor && LightekPeople::LifecycleAccess.active?(actor)
    end

    def owner?
      LightekPeople::Access::BUSINESS_ROLES.include?(actor.role)
    end

    def require_owner!
      LightekPeople::Access.new(actor: actor, employer: actor).require!(:owner)
    end

    def matters
      owned = Matter.where(employer_id: owner? ? actor.id : nil)
      assigned = Matter.where(employer_id: LightekTeam::Workspace.employers_for(actor).select(:id),
        id: MatterReviewer.where(user: actor).select(:matter_id))
      owned.or(assigned)
    end

    def own_mailboxes
      require_owner!
      self.class.mailboxes_for(actor)
    end

    def eligible_reviewers
      require_owner!
      LightekTeam::Workspace.new(actor: actor, employer: actor).roster.where.not(id: actor.id)
    end

    def self.visible?(user)
      access = new(user)
      access.owner? || access.matters.exists?
    rescue LightekPeople::Access::Denied
      false
    end

    def self.mailboxes_for(employer)
      Account.where(user: employer, mailbox_kind: "mailbox")
    end
  end
end
