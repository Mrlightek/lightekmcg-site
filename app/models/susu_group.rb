class SusuGroup < ApplicationRecord
  include Susuable

  belongs_to :organizer, class_name: "User"

  validates :name, presence: true
end