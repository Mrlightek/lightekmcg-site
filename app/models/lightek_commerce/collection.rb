# frozen_string_literal: true

module LightekCommerce
  class Collection < ApplicationRecord
    self.table_name = 'lightek_commerce_collections'

    CONDITION_OPERATORS = {
      'name' => %w[is contains],
      'product_type' => %w[is],
      'price_cents' => %w[at_least at_most],
      'inventory_quantity' => %w[at_least at_most],
      'featured' => %w[is]
    }.freeze
    MAX_CONDITIONS = 10

    belongs_to :site, class_name: 'DymondSite::Site'

    scope :published, -> { where(published: true) }

    before_validation do
      self.slug = name.to_s.parameterize if slug.blank?
      self.product_ids = Array(product_ids).reject(&:blank?).map(&:to_s).uniq
      self.conditions = Array(conditions).map { |condition| condition.to_h.slice('field', 'operator', 'value') }
    end
    before_destroy do
      Discount.where(target_collection: self).update_all(target_collection_id: nil, active: false, updated_at: Time.current)
      Discount.where(qualifying_collection: self).update_all(qualifying_collection_id: nil, active: false, updated_at: Time.current)
    end
    validates :name, presence: true, length: {maximum: 160}
    validates :slug, presence: true, length: {maximum: 180}, uniqueness: {scope: :site_id},
      format: {with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/}
    validates :description, length: {maximum: 2000}
    validates :source, inclusion: {in: %w[manual rules]}
    validates :matching, inclusion: {in: %w[all any]}
    validate :validate_membership

    def products
      catalog = Product.where(site_id: site_id)
      return catalog.where(id: product_ids) if source == 'manual'
      return catalog.none if conditions.blank?

      matches = conditions.map { |condition| matching_products(catalog, condition) }
      if matching == 'all'
        matches.reduce(catalog) { |products, rule| products.where(id: rule.select(:id)) }
      else
        matches.reduce { |products, rule| products.or(rule) }
      end
    end

    private

    def validate_membership
      if source == 'manual'
        if product_ids.size > 2000 || product_ids.any? { |id| !id.match?(/\A[1-9][0-9]{0,17}\z/) } ||
            Product.where(site_id: site_id, id: product_ids).count != product_ids.size
          errors.add(:product_ids, 'must identify products in this store')
        end
      elsif conditions.empty? || conditions.size > MAX_CONDITIONS ||
          conditions.any? { |condition| !valid_condition?(condition) }
        errors.add(:conditions, "must have between 1 and #{MAX_CONDITIONS} valid rules")
      end
    end

    def valid_condition?(condition)
      field, operator, value = condition.values_at('field', 'operator', 'value')
      return false unless CONDITION_OPERATORS.fetch(field, []).include?(operator)

      case field
      when 'name' then value.present? && value.to_s.size <= 160
      when 'product_type' then Product::PRODUCT_TYPES.include?(value)
      when 'featured' then %w[true false].include?(value)
      else value.to_s.match?(/\A[0-9]{1,9}\z/)
      end
    end

    def matching_products(catalog, condition)
      field, operator, value = condition.values_at('field', 'operator', 'value')
      column = Product.arel_table[field]
      case operator
      when 'contains' then catalog.where('LOWER(name) LIKE ?', "%#{Product.sanitize_sql_like(value.downcase)}%")
      when 'at_least' then catalog.where(column.gteq(value.to_i))
      when 'at_most' then catalog.where(column.lteq(value.to_i))
      else
        value = value == 'true' if field == 'featured'
        catalog.where(field => value)
      end
    end
  end
end
