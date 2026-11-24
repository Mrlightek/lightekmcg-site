class ItDeviceMaintenanceAction < ApplicationRecord
  RECOVERY_CHECK = "verify_backup_recovery".freeze
  STAGED_RESTORE = "stage_backup_restore".freeze
  PATCH_DEPLOYMENT = "deploy_apt_patch".freeze
  PATCH_TARGET = /\A[a-z0-9][a-z0-9+.-]{1,127}=[0-9][a-zA-Z0-9.+:~\-]{0,127}\z/
  CONSENT_REQUIRED = [RECOVERY_CHECK, PATCH_DEPLOYMENT, STAGED_RESTORE].freeze
  RECOVERY_DIGEST = /\A[0-9a-f]{64}\z/
  ACTIONS = %w[refresh_inventory check_patch_status check_backup_status check_endpoint_protection verify_backup_recovery deploy_apt_patch stage_backup_restore].freeze
  STATUSES = %w[approved reported expired cancelled].freeze
  belongs_to :network_managed_device
  belongs_to :owner, class_name: "User"
  belongs_to :approved_by, class_name: "User"
  validates :action_code, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :request_nonce, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :expected_recovery_digest, format: { with: RECOVERY_DIGEST }, if: :recovery_check?
  validates :patch_target, format: { with: PATCH_TARGET }, if: :patch_deployment?
  validate :owner_matches_device

  def display_status(now: Time.current)
    return status unless status == "approved"
    return "expired" if expires_at <= now
    return "awaiting_customer_consent" if consent_required? && !owner_consented_at?
    return "scheduled" if starts_at && starts_at > now
    return "running" if claimed_at?

    "awaiting_report"
  end

  def recovery_check?
    [RECOVERY_CHECK, STAGED_RESTORE].include?(action_code)
  end

  def staged_restore?
    action_code == STAGED_RESTORE
  end

  def patch_deployment?
    action_code == PATCH_DEPLOYMENT
  end

  def consent_required?
    CONSENT_REQUIRED.include?(action_code)
  end

  def cancellable?
    return false if patch_deployment? && claimed_at?

    %w[awaiting_customer_consent scheduled awaiting_report running].include?(display_status)
  end

  def owner_matches_device
    errors.add(:owner, "must match device owner") if network_managed_device &&
      owner && network_managed_device.owner_id != owner.id
  end
end
