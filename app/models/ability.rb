# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new   # guest user (not logged in)

    if user.role == "super_admin"
      can :manage, :all

    elsif user.role == "admin"
      can :manage, :all
      cannot :destroy, User, role: "super_admin"

    elsif user.role == "employee"
      can :read,   :all
      can :manage, :portal        # manage client-facing stuff
      can :manage, :projects
      can :manage, :deliverables
      can :read,   DymondBank::Invoice
      can :create, DymondBank::Invoice
      cannot :manage, DymondDash::AppConfig   # can't change CMS settings

    elsif user.role == "contractor"
      can :read,   :dashboard
      can :read,   DymondBank::Payout, recipient: user
      can :read,   DymondBank::RoyaltyPayment

    elsif user.role == "client"
      # Clients only see their own data through the client portal
      can :read,   DymondBank::Invoice,      billable: user
      can :read,   DymondBank::Subscription, subscriber: user
      can :manage, DymondBank::LinkedAccount, linkable: user
      can :read,   :portal
    end
  end
end
