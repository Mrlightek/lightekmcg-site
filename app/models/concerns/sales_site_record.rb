# frozen_string_literal: true
module SalesSiteRecord
  extend ActiveSupport::Concern
  included do
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :owner, class_name: 'User', optional: true
    validate :sales_owner_has_site_access
  end
  private
  def sales_owner_has_site_access
    if owner_id.present? && site && !LightekSales::Access.owners_for(site).exists?(id: owner_id)
      errors.add(:owner, 'must be an owner or sales-enabled member of this website')
    end
  end
  def same_sales_site(attribute)
    record = public_send(attribute)
    errors.add(attribute, 'must belong to this website') if record && record.site_id != site_id
  end
end
