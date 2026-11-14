require 'digest'
require 'json'
module LightekAgency
  # Package permissions restrict existing authorization; they never grant a role,
  # an administrator capability, provider access or another account's data.
  class PackagePolicy
    class Denied < StandardError; end
    FEATURES = {
      'website' => 'Websites & pages', 'design' => 'Design & content', 'studio' => 'Photo, video & production Studio',
      'live' => 'Live broadcasting', 'rooms' => 'Voice & video rooms', 'reservations' => 'Reservations',
      'commerce' => 'Commerce', 'shipping' => 'Shipping', 'marketing' => 'Marketing & social publishing',
      'mail' => 'Communications & mail', 'accounting' => 'Bookkeeping & accounting', 'people' => 'People & payroll',
      'compliance' => 'Legal & compliance', 'directory' => 'Directory & access', 'community' => 'Communities & profiles',
      'messaging' => 'Direct messaging', 'susu' => 'Susu', 'pwa' => 'PWA', 'ott' => 'OTT & channels',
      'knowledge' => 'Knowledge base', 'payments' => 'Payments & payouts', 'nevaeh' => 'Nevaeh & automation', 'agency' => 'Agency & reseller tools'
    }.freeze
    LIMITS = {'max_sites' => 'Websites', 'max_users' => 'User accounts', 'max_storage_bytes' => 'Media storage (bytes)'}.freeze
    ALIASES = {'commerce_workspace'=>'commerce','bookkeeping_workspace'=>'accounting','agency_workspace'=>'agency','white_label_agency'=>'agency','money'=>'susu','space'=>'community','messages'=>'messaging','create'=>'community','communities'=>'community','mail_workspace'=>'mail'}.freeze
    def self.defaults
      {'features' => FEATURES.keys.to_h { |key| [key, {'enabled' => true, 'monthly_writes' => nil}] }, 'limits' => LIMITS.keys.to_h { |key| [key, nil] }}
    end
    def self.normalize(raw)
      raise Denied, 'Package settings must be an object' unless raw.respond_to?(:to_h)
      raw = raw.to_h.deep_stringify_keys
      raise Denied, 'Feature and limit settings must be objects' unless raw.fetch('features', {}).is_a?(Hash) && raw.fetch('limits', {}).is_a?(Hash)
      raise Denied, 'Unknown package settings' unless (raw.keys - %w[features limits]).empty?
      raise Denied, 'Unknown package feature' unless (raw.fetch('features', {}).keys - FEATURES.keys).empty?
      raise Denied, 'Unknown package resource limit' unless (raw.fetch('limits', {}).keys - LIMITS.keys).empty?
      result = defaults
      raw.fetch('features', {}).each do |key, value|
        raise Denied, 'Feature settings must be an object' unless value.is_a?(Hash) && (value.keys - %w[enabled monthly_writes]).empty?
        enabled = value.fetch('enabled', true)
        raise Denied, 'Choose enabled or disabled' unless [true, false, '0', '1'].include?(enabled)
        result['features'][key] = {'enabled' => [true, '1'].include?(enabled), 'monthly_writes' => limit(value['monthly_writes'])}
      end
      raw.fetch('limits', {}).each do |key, value|
        result['limits'][key] = limit(value)
        raise Denied, 'Website and user limits include the initial website and owner; use at least one.' if key != 'max_storage_bytes' && result['limits'][key] == 0
      end
      result
    end
    def self.limit(value)
      return nil if value.nil? || value == ''
      raise Denied, 'Limits must be whole numbers or unlimited' unless value.to_s.match?(/\A\d+\z/) && value.to_i <= 9_000_000_000_000_000
      value.to_i
    end
    def self.restrict!(upstream:, requested:)
      parent = normalize(upstream)
      # Omitted settings inherit. Explicit unlimited may never remove a ceiling.
      raw = requested.to_h.deep_stringify_keys
      child = normalize(parent.deep_merge(raw))
      FEATURES.each_key do |key|
        p = parent['features'][key]; c = child['features'][key]
        raise Denied, "#{FEATURES[key]} is disabled by Lightek" if c['enabled'] && !p['enabled']
        raise Denied, "#{FEATURES[key]} exceeds the upstream allowance" if p['monthly_writes'] && (c['monthly_writes'].nil? || c['monthly_writes'] > p['monthly_writes'])
      end
      LIMITS.each_key do |key|
        p = parent['limits'][key]; c = child['limits'][key]
        raise Denied, "#{LIMITS[key]} exceeds the upstream allowance" if p && (c.nil? || c > p)
      end
      child
    end
    def self.for_product(product)
      if product.respond_to?(:source_hosting_package) && product.source_hosting_package
        return restrict!(upstream: normalize(product.source_hosting_package.product.package_policy), requested: product.package_policy)
      end
      normalize(product.respond_to?(:package_policy) ? product.package_policy : {})
    end
    def self.canonical(value)
      case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |entry| canonical(entry) }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end
    def self.digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(normalize(value))))
    def self.available? = InstalledPackage.table_exists?
    def self.runtime_accounts
      return InstalledPackage.none unless available?
      InstalledPackage.where(runtime: true)
    end
    def self.accounts_for(user)
      return InstalledPackage.none unless available?
      return runtime_accounts unless user
      ids = [user.id]
      ids += user.account_ancestors.map(&:id) if user.respond_to?(:account_ancestors)
      InstalledPackage.where(user_id: ids).or(InstalledPackage.where(id: runtime_accounts.select(:id)))
    end
    def self.allowed?(user, feature)
      feature = ALIASES.fetch(feature.to_s, feature.to_s)
      return true unless FEATURES.key?(feature)
      accounts_for(user).all? { |account| normalize(account.policy)['features'][feature]['enabled'] }
    end
    def self.authorize!(user, feature)
      raise Denied, "#{FEATURES[ALIASES.fetch(feature.to_s, feature.to_s)] || feature} is not included in this account's package." unless allowed?(user, feature)
      true
    end
    def self.install!(user:, configuration:)
      return unless configuration.present?
      data = configuration.deep_stringify_keys
      user.with_lock do
        installed = InstalledPackage.find_or_initialize_by(user: user)
        if installed.persisted? && installed.source_key != data.fetch('source_key')
          raise Denied, 'This installation already belongs to another package purchase'
        end
        installed.update!(source_key: data.fetch('source_key'), runtime: true, policy: normalize(data.fetch('policy')))
      end
    end
    def self.reserve_write!(user:, feature:, now: Time.current)
      return [] unless FEATURES.key?(feature)
      reservations = []
      begin
        accounts_for(user).order(:id).each do |account|
          account.with_lock do
            settings = normalize(account.policy)['features'][feature]
            raise Denied, "#{FEATURES[feature]} is disabled by your package." unless settings['enabled']
            ceiling = settings['monthly_writes']
            next unless ceiling
            usage = account.usages.find_or_create_by!(feature: feature, period: now.utc.to_date.beginning_of_month)
            raise Denied, "#{FEATURES[feature]} has reached its monthly write allowance." if usage.used >= ceiling
            usage.increment!(:used)
            reservations << usage.id
          end
        end
      rescue StandardError
        release_write!(reservations)
        raise
      end
      reservations
    end
    def self.release_write!(ids)
      PackageUsage.where(id: ids).where('used > 0').update_all('used = used - 1') if ids.present?
    end
  end
end
