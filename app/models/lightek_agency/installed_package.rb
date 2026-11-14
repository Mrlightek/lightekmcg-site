module LightekAgency
  class InstalledPackage < ApplicationRecord
    self.table_name = 'lightek_agency_installed_packages'
    belongs_to :user
    has_many :usages, class_name: 'LightekAgency::PackageUsage', dependent: :destroy
    has_many :storage, class_name: 'LightekAgency::PackageStorage', dependent: :destroy
    validates :source_key, presence: true
    validates :user_id, uniqueness: true
    validate { PackagePolicy.normalize(policy) }
  end
end
