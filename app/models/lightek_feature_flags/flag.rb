require "digest"

module LightekFeatureFlags
  class Flag < ApplicationRecord
    self.table_name = "lightek_feature_flags"
    class Unavailable < StandardError; end

    REGISTRY = {
      "managed_dns" => {
        label: "Managed DNS",
        description: "Controls new enrollments and cutover approvals. Active domains retain record access."
      }.freeze
    }.freeze
    SETTINGS = %w[enabled staff percentage account_ids agency_ids installation_ids].freeze

    has_many :revisions, class_name: "LightekFeatureFlags::Change", dependent: :restrict_with_exception
    attr_readonly :key
    validates :key, inclusion: {in: REGISTRY.keys}
    validates :percentage, numericality: {only_integer: true, in: 0..100}

    def self.enabled?(key, account:, installation: nil)
      configured(key)&.allows?(account:, installation:) == true
    end

    def self.with_enabled!(key, account:, installation: nil)
      flag = configured(key)
      raise Unavailable, "This rollout is paused for this account." unless flag

      flag.with_lock do
        raise Unavailable, "This rollout is paused for this account." unless flag.allows?(account:, installation:)
        yield
      end
    end

    def self.configured(key)
      find_by(key: key) if REGISTRY.key?(key) && table_exists?
    end

    def allows?(account:, installation: nil)
      return false unless enabled? && account&.persisted? && LightekPeople::LifecycleAccess.active?(account)
      return true if account_ids.include?(account.id)
      return true if staff? && lightek_staff?(account)
      return true if agency_ids.any? && ([account] + account.account_ancestors).any? { |parent| parent.white_label? && agency_ids.include?(parent.id) }

      if installation_ids.any?
        target = installation&.call
        return true if target&.account_id == account.id && installation_ids.include?(target.id)
      end

      percentage.positive? && rollout_bucket(account.id) < percentage * 100
    end

    def revise!(actor:, attributes:, expected_version: nil)
      raise Unavailable, "Platform operator access is required." unless Gatekeeper::Hosting::Access.super_admin?(actor)

      with_lock do
        if expected_version && expected_version != lock_version
          raise Unavailable, "This flag changed. Reload it before saving."
        end
        previous = attributes_snapshot
        update!(attributes)
        current = attributes_snapshot
        revisions.create!(actor: actor, previous: previous, current: current) if current != previous
      end
    end

    def attributes_snapshot
      attributes.slice(*SETTINGS)
    end

    private

    def rollout_bucket(account_id)
      Digest::SHA256.digest("#{key}:#{account_id}").unpack1("Q>") % 10_000
    end

    def lightek_staff?(account)
      account.role == "super_admin" ||
        LightekPeople::Employment.active.where(worker_id: account.id, worker_kind: "employee",
          employer_id: User.where(role: "super_admin", access_suspended_at: nil).select(:id)).exists?
    end
  end
end
