# frozen_string_literal: true

module LightekShipping
  class Supplies
    COLLECTION_SLUG = 'packing-supplies'

    def self.catalog_site_id
      operators = User.where(role: 'super_admin').select(:id)
      stores = DymondSite::Site.where(tenant_type: 'User', tenant_id: operators)
      catalog = LightekCommerce::Collection.published.where(site_id: stores.select(:id), slug: COLLECTION_SLUG)
        .order(:site_id).find do |collection|
          collection.products.merge(LightekCommerce::Product.visible).exists?(product_type: 'physical')
        end
      catalog&.site_id
    end
  end
end
