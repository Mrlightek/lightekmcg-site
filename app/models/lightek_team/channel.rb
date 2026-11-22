# frozen_string_literal: true

module LightekTeam
  class Channel < ApplicationRecord
    self.table_name = 'lightek_team_channels'

    belongs_to :employer, class_name: 'User'
    belongs_to :creator, class_name: 'User'
    has_many :memberships, class_name: 'LightekTeam::Membership', dependent: :destroy
    has_many :messages, class_name: 'LightekTeam::Message', dependent: :restrict_with_error

    normalizes :name, with: ->(name) { name.strip.downcase }
    validates :name, length: {in: 2..60}, format: {with: /\A[a-z0-9][a-z0-9-]*\z/, allow_blank: true},
      uniqueness: {scope: :employer_id}
    validates :description, length: {maximum: 240}
  end
end
