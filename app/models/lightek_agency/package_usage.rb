module LightekAgency
  class PackageUsage < ApplicationRecord
    self.table_name = 'lightek_agency_package_usages'
    belongs_to :installed_package, class_name: 'LightekAgency::InstalledPackage'
  end
end
