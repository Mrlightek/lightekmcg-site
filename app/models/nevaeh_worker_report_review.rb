# frozen_string_literal: true
class NevaehWorkerReportReview < ApplicationRecord
  belongs_to :nevaeh_worker_report
  belongs_to :user
  validates :verdict, inclusion: {in: %w[accepted needs_fix rejected withdrawn]}
  validates :lesson, length: {maximum: 2000}
  validates :receipt_sha256, format: {with: /\A[0-9a-f]{64}\z/}
  validate do
    errors.add(:user, 'must own the report') if nevaeh_worker_report && nevaeh_worker_report.user_id != user_id
    errors.add(:base, 'Report reviews are append-only') if persisted? && changed?
  end
  before_destroy { throw :abort }
end
