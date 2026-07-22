# frozen_string_literal: true

class User < ApplicationRecord
  # ── Rails 8 native authentication ─────────────────────────────────────────────
  has_secure_password

  # Normalise email_address before save
  normalizes :email_address, with: -> e { e.strip.downcase }

  # ── Validations ───────────────────────────────────────────────────────────────
  validates :email_address,      presence: true, uniqueness: true,
                         format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, presence: true
  validates :last_name,  presence: true

  ROLES = %w[client employee contractor admin super_admin].freeze
  validates :role, inclusion: { in: ROLES }

  # ── Associations — DymondBank ─────────────────────────────────────────────────
  # A user's internal DymondBank ledger accounts
  has_many :bank_accounts,    class_name: "DymondBank::Account",
                              as: :accountable,
                              dependent: :restrict_with_error

  # Linked external bank accounts (Plaid)
  has_many :linked_accounts,  class_name: "DymondBank::LinkedAccount",
                              as: :linkable,
                              dependent: :destroy

  # Subscription plan
  has_one  :subscription,     class_name: "DymondBank::Subscription",
                              as: :subscriber

  # Invoices billed to this user
  has_many :invoices,         class_name: "DymondBank::Invoice",
                              as: :billable

  # Payouts received by this user
  has_many :payouts,          class_name: "DymondBank::Payout",
                              as: :recipient

  # Royalty splits this user is entitled to
  has_many :royalty_splits,   class_name: "DymondBank::RoyaltySplit",
                              as: :recipient

  # Account plan for DymondDash feature gating
  has_one  :account_plan,     class_name: "DymondDash::AccountPlan",
                              as: :account

  # ── Helpers ────────────────────────────────────────────────────────────────────
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def initials
    [first_name.first, last_name.first].join.upcase
  end

  def admin?       = role.in?(%w[admin super_admin])
  def employee?    = role.in?(%w[employee admin super_admin])
  def client?      = role == "client"
  def contractor?  = role == "contractor"

  # ── DymondDash role gating ─────────────────────────────────────────────────────
  # Called by FeatureRegistry#role_allows? — return false to hide a nav item
  def can_access_feature?(feature_slug)
    case feature_slug.to_sym
    when :dymond_bank
      employee? || admin?
    when :lightek_studio
      employee? || admin?
      when :employee_clients
    employee? || admin?
    when :employee_tickets
    employee? || admin?
    when :employee_users
  admin?
    else
      true
    end
  end

  # ── DymondBank — default linked bank account ───────────────────────────────────
  def default_linked_account
    linked_accounts.active.find_by(is_default: true) ||
      linked_accounts.active.first
  end

  # ── DymondDash — current plan slug for nav gating ─────────────────────────────
  def current_plan_slug
    account_plan&.plan_slug || "starter"
  end

  # ── Sessions (Rails 8 auth) ───────────────────────────────────────────────────
  generates_token_for :email_verification, expires_in: 2.days do
    email_address
  end

  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt.last(10)
  end

  has_many :sessions, dependent: :destroy
end
