# frozen_string_literal: true

module ReleaseAssurance
  class Tester < ApplicationRecord
    self.table_name = "release_assurance_testers"

    PLATFORMS = %w[windows macos linux].freeze

    belongs_to :operator, class_name: "User"
    has_many :assignments, class_name: "ReleaseAssurance::Assignment"

    normalizes :email, with: ->(email) { email.strip.downcase }
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
    validates :name, :device_profile, presence: true, length: { maximum: 120 }
    validates :platform, inclusion: { in: PLATFORMS }
    validates :consented_at, presence: true
  end
end
