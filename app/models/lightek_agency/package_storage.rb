module LightekAgency
  class PackageStorage < ApplicationRecord
    self.table_name = 'lightek_agency_package_storage'
    belongs_to :installed_package, class_name: 'LightekAgency::InstalledPackage'
  end
end
