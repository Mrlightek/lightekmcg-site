# frozen_string_literal: true

class NevaehExecutiveCase < ApplicationRecord
  KINDS = {
    'follow_up' => 'Follow-up', 'call' => 'Call triage', 'travel' => 'Travel booking',
    'expense' => 'Expense review', 'contract' => 'Contract review', 'screening' => 'Screening delivery'
  }.freeze

  belongs_to :owner, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :reviewer, class_name: 'User', optional: true
  belongs_to :delivery_message, class_name: 'LightekMail::Message', optional: true
  has_one_attached :material
  has_one_attached :completion_material
  validates :title, presence: true, length: {maximum: 160}
  validates :details, :review_note, length: {maximum: 8_000}
  validates :reference, length: {maximum: 240}
  validates :kind, inclusion: {in: KINDS.keys}
  validates :status, inclusion: {in: %w[open in_review reviewed needs_changes closed]}
  validates :due_at, presence: true
  validate :bounded_material
  scope :pending, -> { where.not(status: 'closed') }
  scope :ready_for_reminder, -> { pending.where(reminded_at: nil).where('due_at <= ?', Time.current) }

  def self.visible_to(actor)
    employers = LightekPeople::Employment.active.where(worker: actor).select(:employer_id)
    owners = User.where(id: employers, access_suspended_at: nil)
    where(owner: actor).or(where(assignee: actor, owner: owners))
  end

  def kind_label = KINDS.fetch(kind)

  private

  def bounded_material
    %i[material completion_material].each do |attribute|
      attachment = public_send(attribute)
      errors.add(attribute, 'must be at most 10 MB') if attachment.attached? && attachment.blob.byte_size > 10.megabytes
    end
  end
end
