# frozen_string_literal: true

class StudioSceneRender < ApplicationRecord
  class ClaimLost < StandardError; end

  belongs_to :studio_scene
  has_many_attached :inputs
  has_one_attached :video

  RUNNING_STATUSES = %w[preparing rendering encoding].freeze
  ACTIVE_STATUSES = (%w[queued] + RUNNING_STATUSES).freeze
  QUEUE_TIMEOUT = 30.minutes
  LEASE_DURATION = 3.minutes
  REQUEST_ID_FORMAT = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/

  validates :status, inclusion: { in: ACTIVE_STATUSES + %w[completed failed] }
  validates :progress, inclusion: { in: 0..100 }
  validates :request_id, format: { with: REQUEST_ID_FORMAT }, allow_nil: true
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def self.expire_stale!
    now = Time.current
    queued = where(status: "queued", created_at: ..(now - QUEUE_TIMEOUT))
    running = where(status: RUNNING_STATUSES)
    expired = running.where(lease_expires_at: ..now)
    legacy = running.where(lease_expires_at: nil, updated_at: ..(now - LEASE_DURATION))
    queued.or(expired).or(legacy).find_each(&:expire_if_stale!)
  end

  def active? = ACTIVE_STATUSES.include?(status)

  def expire_if_stale!
    with_lock { expire_locked!(Time.current) } if active?
  end

  def claim!
    with_lock do
      now = Time.current
      expire_locked!(now)
      next unless status == "queued"
      token = SecureRandom.uuid
      update!(status: "preparing", progress: 2, claim_token: token, lease_expires_at: now + LEASE_DURATION)
      token
    end
  end

  def with_claim!(token, expected)
    with_lock do
      now = Time.current
      unless token.present? && claim_token == token && Array(expected).include?(status) &&
          lease_expires_at && lease_expires_at > now
        raise ClaimLost
      end
      yield now
    end
  end

  def advance_claim!(token, expected, **attributes)
    with_claim!(token, expected) do |now|
      update!(lease_expires_at: now + LEASE_DURATION, **attributes)
    end
  end

  def mark_failed!(message)
    update!(failed_phase: status, status: "failed", error_message: message, claim_token: nil, lease_expires_at: nil)
  end

  private

  def expire_locked!(now)
    if status == "queued" && created_at <= now - QUEUE_TIMEOUT
      mark_failed!("The render did not start in time. Retry this render to send it back to the queue.")
    elsif RUNNING_STATUSES.include?(status) && (lease_expires_at || updated_at + LEASE_DURATION) <= now
      mark_failed!("The worker stopped reporting progress. Retry this render from the saved snapshot.")
    end
  end
end
