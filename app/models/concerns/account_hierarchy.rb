module AccountHierarchy
  extend ActiveSupport::Concern
  included do
    validates :upstream_share_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000}
    validate :valid_account_parent
  end

  def managed_account_ids
    return [] unless id
    seen = [id]
    frontier = [id]
    until frontier.empty?
      frontier = User.where(agency_id: frontier).where.not(id: seen).pluck(:id)
      seen.concat(frontier)
    end
    seen
  end

  def account_ancestors
    seen = [id].compact
    result = []
    cursor = agency
    while cursor
      raise ArgumentError, "Account hierarchy contains a cycle" if seen.include?(cursor.id)
      seen << cursor.id
      result << cursor
      cursor = cursor.agency
    end
    result
  end

  def account_branding_profile
    ([self] + account_ancestors).filter_map(&:agency_profile).first
  end

  private
  def valid_account_parent
    return unless agency_id.present?
    if agency_id == id || !role.in?(%w[client white_label]) || !agency&.role.in?(%w[super_admin white_label client])
      errors.add(:agency, "must be an upstream reseller account")
      return
    end
    errors.add(:agency, "cannot be one of this account's descendants") if agency.account_ancestors.any? { |ancestor| ancestor.id == id }
  rescue ArgumentError => error
    errors.add(:agency, error.message)
  end
end
