class StudioAsset < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :site, class_name: "DymondSite::Site", optional: true
  belongs_to :studio_project, optional: true
  has_one_attached :file
  has_one_attached :proxy
  has_one_attached :thumbnail
  validates :name, presence: true, length: { maximum: 160 }
  validates :kind, inclusion: { in: %w[image audio video blend glb] }
  validates :status, inclusion: { in: %w[uploaded processing ready failed] }
  validates :request_key, presence: true, uniqueness: { scope: :owner_id }
  def self.for_actor(access)
    return all if access.user.role == "super_admin"
    if access.site_id && %w[admin editor].include?(LightekPwa::Policy.new(user: access.user, site: DymondSite::Site.find(access.site_id)).role)
      return where(site_id: access.site_id)
    end
    where(owner_id: access.user.id, site_id: access.site_id)
  end
end
