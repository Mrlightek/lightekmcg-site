module LightekAgency
  class PackageLimits
    def self.operator_override?
      defined?(Current) && Current.respond_to?(:session) && Current.session&.user&.role == 'super_admin'
    end
    def self.with_limit(key)
      return yield unless PackagePolicy.available? && !operator_override?
      accounts = PackagePolicy.runtime_accounts.order(:id).to_a
      lock_accounts(accounts, 0) do
        ceilings = accounts.filter_map { |account| PackagePolicy.normalize(account.policy)['limits'][key] }
        yield ceilings.min
      end
    end
    def self.lock_accounts(accounts, index, &block)
      return yield if index == accounts.size
      accounts[index].with_lock { lock_accounts(accounts, index + 1, &block) }
    end
    def self.check_users!
      with_limit('max_users') do |ceiling|
        raise PackagePolicy::Denied, 'This instance has reached its user account allowance.' if ceiling && User.count >= ceiling
      end
    end
    def self.check_sites!
      with_limit('max_sites') do |ceiling|
        raise PackagePolicy::Denied, 'This instance has reached its website allowance.' if ceiling && DymondSite::Site.count >= ceiling
      end
    end
    def self.preflight_blob!(blob)
      storage_transaction(blob, reserve: false)
    end
    def self.reserve_storage!(attachment)
      storage_transaction(attachment.blob, reserve: true)
    end
    def self.reserve_blob!(blob)
      storage_transaction(blob, reserve: true)
    end
    def self.storage_transaction(blob, reserve:)
      return if operator_override? || !PackagePolicy.available? || !blob
      accounts = PackagePolicy.runtime_accounts.order(:id).to_a
      lock_accounts(accounts, 0) do
        attached_ids = ActiveStorage::Attachment.select(:blob_id)
        accounts.each do |account|
          ceiling = PackagePolicy.normalize(account.policy)['limits']['max_storage_bytes']
          next unless ceiling
          next if blob.persisted? && account.storage.exists?(blob_id: blob.id)
          attached = ActiveStorage::Blob.where(id: attached_ids).sum(:byte_size)
          reserved = account.storage.where.not(blob_id: attached_ids).sum(:bytes)
          addition = blob.persisted? && ActiveStorage::Attachment.exists?(blob_id: blob.id) ? 0 : blob.byte_size
          raise PackagePolicy::Denied, 'This instance has reached its media storage allowance.' if attached + reserved + addition > ceiling
          account.storage.create!(blob_id: blob.id, bytes: blob.byte_size) if reserve && blob.persisted?
        end
      end
    end
    def self.release_blob!(id)
      PackageStorage.where(blob_id: id).delete_all if PackagePolicy.available?
    end
    def self.install_callbacks!
      %w[DymondDash DymondBooking DymondKb DymondCatalog DymondStudio DymondBank DymondSocial DymondConnect].each do |name|
        next unless Object.const_defined?(name)
        engine = Object.const_get(name)
        next unless engine.const_defined?(:ApplicationController)
        controller = engine.const_get(:ApplicationController)
        controller.include(LightekAgencyPackageAccess) unless controller < LightekAgencyPackageAccess
      end
      # Model callbacks also cover internal workers; quotas are not menu-only checks.
      unless User._create_callbacks.any? { |callback| callback.filter == :check_installed_package_user_limit }
        User.class_eval do
          before_create :check_installed_package_user_limit
          def check_installed_package_user_limit = LightekAgency::PackageLimits.check_users!
        end
      end
      if defined?(DymondSite::Site) && !DymondSite::Site._create_callbacks.any? { |callback| callback.filter == :check_installed_package_site_limit }
        DymondSite::Site.class_eval do
          before_create :check_installed_package_site_limit
          def check_installed_package_site_limit = LightekAgency::PackageLimits.check_sites!
        end
      end
      if defined?(ActiveStorage::Attachment) && !ActiveStorage::Attachment._create_callbacks.any? { |callback| callback.filter == :check_installed_package_storage_limit }
        ActiveStorage::Attachment.class_eval do
          before_create :check_installed_package_storage_limit
          def check_installed_package_storage_limit = LightekAgency::PackageLimits.reserve_storage!(self)
        end
        ActiveStorage::Blob.class_eval do
          before_create :preflight_installed_package_storage
          after_create :reserve_installed_package_storage
          def preflight_installed_package_storage = LightekAgency::PackageLimits.preflight_blob!(self)
          def reserve_installed_package_storage = LightekAgency::PackageLimits.reserve_blob!(self)
          after_destroy_commit :release_installed_package_storage
          def release_installed_package_storage = LightekAgency::PackageLimits.release_blob!(id)
        end
      end
    end

  end
end
