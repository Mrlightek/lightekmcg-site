# frozen_string_literal: true
# Schema prepared in Phase 6A; NO runtime integration until migration and
# transactional execution/replay tests have been separately approved.
class NevaehStudioIdempotencyRecord < ApplicationRecord
  validates :operation_key, :ticket_id, :work_order_sha256, :inputs_sha256,
    :work_item_id, :studio_project_id, :production_id, :studio_scene_id,
    presence: true
  validates :operation_key, uniqueness: true
  validates :work_order_sha256, :inputs_sha256,
    format: { with: /\A[0-9a-f]{64}\z/ }
end
