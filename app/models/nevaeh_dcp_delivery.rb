class NevaehDcpDelivery < ApplicationRecord
  belongs_to :executive_case, class_name: 'NevaehExecutiveCase'
  belongs_to :recipient, class_name: 'User'
  has_one_attached :package

  validates :rights_reference, presence: true, length: {maximum: 240}
  validates :expires_at, presence: true

  def available?
    status == 'ready' && !revoked_at? && expires_at.future? &&
      LightekPeople::LifecycleAccess.active?(executive_case.owner) &&
      LightekPeople::LifecycleAccess.active?(recipient)
  end
end
