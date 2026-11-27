# frozen_string_literal: true

require 'securerandom'

module LightekCommerce
  class InventoryStockStates
    class Invalid < StandardError; end

    COLUMNS = {
      'available' => :inventory_quantity, 'incoming' => :incoming_quantity,
      'unavailable' => :unavailable_quantity, 'damaged' => :damaged_quantity
    }.freeze
    MOVEMENTS = {
      'expect' => ['Record incoming stock', nil, 'incoming'],
      'receive' => ['Receive incoming stock', 'incoming', 'available'],
      'cancel' => ['Cancel incoming stock', 'incoming', nil],
      'hold' => ['Mark stock unavailable', 'available', 'unavailable'],
      'release' => ['Release unavailable stock', 'unavailable', 'available'],
      'damage' => ['Mark available stock damaged', 'available', 'damaged'],
      'damage_held' => ['Mark unavailable stock damaged', 'unavailable', 'damaged'],
      'restore' => ['Restore damaged stock', 'damaged', 'available'],
      'write_off' => ['Write off damaged stock', 'damaged', nil]
    }.freeze

    def self.move!(site:, actor:, product_id:, variant_id:, movement:, quantity:, version:)
      _, from, to = MOVEMENTS.fetch(movement) { raise Invalid, 'Choose a stock movement.' }
      unless product_id.to_s.match?(/\A[1-9][0-9]{0,18}\z/) &&
          (variant_id.blank? || variant_id.to_s.match?(/\A[1-9][0-9]{0,18}\z/))
        raise Invalid, 'Choose a tracked product or option.'
      end
      max = InventoryAdjustment::MAX_QUANTITY
      unless quantity.to_s.match?(/\A[1-9][0-9]{0,9}\z/) && quantity.to_i <= max
        raise Invalid, "Enter a whole quantity from 1 to #{max}."
      end
      units = quantity.to_i
      Product.transaction do
        product = Product.where(site: site).where.not(product_type: 'lightek_instance').lock.find(product_id)
        target = if variant_id.present?
          product.variants.where(active: true).lock.find(variant_id)
        elsif product.track_inventory? && !product.variants.where(active: true).exists?
          product
        end
        raise Invalid, 'This item no longer has tracked stock.' unless target
        unless version == InventoryAdjustment.snapshot_version(target.updated_at)
          raise Invalid, 'Stock changed since you opened this page. Review the counts and try again.'
        end

        apply_locked!(product: product, target: target, from: from, to: to, units: units, actor: actor)
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::Deadlocked
      raise Invalid, 'Another inventory transaction is in progress. Try the adjustment again.'
    end

    # Caller locks the product, then its variant when present, inside the stock transaction.
    def self.apply_locked!(product:, target:, from:, to:, units:, actor:, supplier_order: nil)
      max = InventoryAdjustment::MAX_QUANTITY
      deltas = {}
      deltas[from] = -units if from
      deltas[to] = units if to
      counts = deltas.to_h do |state, delta|
        before = target[COLUMNS.fetch(state)]
        after = before + delta
        raise Invalid, "There are only #{before} #{state} units." if after.negative?
        raise Invalid, "The #{state} count cannot exceed #{max} units." if after > max

        [state, [before, after]]
      end
      updates = counts.to_h { |state, (_, after)| [COLUMNS.fetch(state), after] }
      if counts.key?('incoming')
        supplier_incoming = target.supplier_incoming_quantity
        if supplier_order
          supplier_incoming += deltas.fetch('incoming')
          updates[:supplier_incoming_quantity] = supplier_incoming
        end
        unless supplier_incoming.between?(0, updates.fetch(:incoming_quantity))
          raise Invalid, 'Receive or cancel supplier stock from its purchase order.'
        end
      end
      target.update!(updates)
      batch_key = SecureRandom.uuid
      counts.each do |state, (before, after)|
        InventoryChange.record!(product: product, variant: (target unless target.equal?(product)), actor: actor,
          source: 'stock_state_adjustment', stock_state: state, batch_key: batch_key, supplier_order: supplier_order,
          before_quantity: before, after_quantity: after)
      end
    end

    def self.allocated?(target)
      COLUMNS.except('available').values.any? { |column| target[column].positive? }
    end
  end
end
