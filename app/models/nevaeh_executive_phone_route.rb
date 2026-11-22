# frozen_string_literal: true

class NevaehExecutivePhoneRoute < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true

  def secret_slug = "executive-phone-#{key}"
end
