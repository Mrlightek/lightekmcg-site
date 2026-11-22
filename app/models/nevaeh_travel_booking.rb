class NevaehTravelBooking < ApplicationRecord
  belongs_to :executive_case, class_name: 'NevaehExecutiveCase'
end
