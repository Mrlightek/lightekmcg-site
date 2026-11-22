# frozen_string_literal: true

module LightekGrowth
  class PressContact < ApplicationRecord
    self.table_name = 'lightek_press_contacts'

    validates :email, :outlet, :contact_basis, presence: true
  end
end
