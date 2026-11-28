# frozen_string_literal: true

module LightekCommerce
  class ReturnFeePolicy
    class Invalid < StandardError; end

    KEY = 'commerce_return_fee_policy'
    MODES = {'No default fee' => 'none', 'Fixed fee per return' => 'fixed',
             'Percentage of returned merchandise' => 'percentage'}.freeze

    def self.read(site)
      value = site.manifest.to_h[KEY]
      return {'mode' => 'none'} unless value.is_a?(Hash)

      case value['mode']
      when 'fixed'
        return value.slice('mode', 'fixed_cents') if valid_amount?(value['fixed_cents'], InventoryAdjustment::MAX_QUANTITY)
      when 'percentage'
        return value.slice('mode', 'percent') if valid_amount?(value['percent'], 99)
      end
      {'mode' => 'none'}
    end

    def self.save!(site, input)
      values = case input[:mode]
      when 'none'
        {'mode' => 'none'}
      when 'fixed'
        value = input[:fixed_cents]
        unless valid_amount?(value, InventoryAdjustment::MAX_QUANTITY)
          raise Invalid, 'Enter the fixed return fee as a positive whole number of cents.'
        end

        {'mode' => 'fixed', 'fixed_cents' => value.to_i}
      when 'percentage'
        value = input[:percent]
        raise Invalid, 'Enter a whole return fee percentage from 1 to 99.' unless valid_amount?(value, 99)

        {'mode' => 'percentage', 'percent' => value.to_i}
      else
        raise Invalid, 'Choose a return fee rule.'
      end
      site.with_lock { site.update!(manifest: site.manifest.to_h.merge(KEY => values)) }
    end

    def self.suggested_cents(site:, order:, item:, record:)
      policy = read(site)
      case policy['mode']
      when 'fixed'
        fee = policy.fetch('fixed_cents').to_i
      when 'percentage'
        fee = ReturnRefunds.minimum_merchandise_amount(item, record) * policy.fetch('percent').to_i / 100
      else
        return 0
      end

      [fee, ReturnRefunds.maximum_fee_cents(order, item, record)].min
    end

    def self.valid_amount?(value, max)
      value.to_s.match?(/\A[1-9][0-9]{0,9}\z/) && value.to_i <= max
    end
    private_class_method :valid_amount?
  end
end
