# frozen_string_literal: true
class NevaehTestRun < ApplicationRecord
  STATUSES = %w[passed failed].freeze
  validates :run_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :output_sha256, :report_path, :output_path, presence: true
  belongs_to :nevaeh_capability, optional: true
  belongs_to :marlon_ticket, class_name: "Marlon::Ticket", optional: true
  scope :recent_first, -> { order(started_at: :desc, id: :desc) }
  scope :failed, -> { where(status: "failed") }
  scope :for_capability, ->(slug) { where(capability_slug: slug.to_s) }

  def self.summary_for(capability:)
    runs = for_capability(capability)
    { "capability" => capability.to_s, "total_runs" => runs.count,
      "failed_runs" => runs.failed.count,
      "latest" => runs.recent_first.first&.slice("run_id", "status", "git_sha", "started_at") }
  end
end
