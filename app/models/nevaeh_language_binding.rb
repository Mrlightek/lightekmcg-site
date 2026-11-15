# frozen_string_literal: true
require 'digest'
class NevaehLanguageBinding < ApplicationRecord
  belongs_to :creator, class_name: 'User'
  belongs_to :nevaeh_manual_build, optional: true
  validates :name, presence: true, length: {maximum: 160}
  validates :status, inclusion: {in: %w[draft active paused]}
  validate do
    begin
      NevaehOs::LanguageContract.validate!(patterns: patterns, slots: slots, command: command_template, sources: source_refs)
    rescue ArgumentError => error
      errors.add(:base, error.message)
    end
  end
  before_update do
    self.status = 'draft' if %w[patterns slots command_template source_refs].any? { |field| will_save_change_to_attribute?(field) }
  end
  def fingerprint
    Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump({patterns: patterns, slots: slots, command: command_template, sources: source_refs, contract_sha256: contract_sha256}))
  end
end
