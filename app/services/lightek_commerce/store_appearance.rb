# frozen_string_literal: true

module LightekCommerce
  class StoreAppearance
    class Invalid < StandardError; end

    KEY = 'commerce_store_appearance'
    MAX_LENGTHS = {'brand_name' => 48, 'checkout_title' => 80, 'checkout_message' => 280,
                   'account_title' => 80, 'account_message' => 280}.freeze
    FIELDS = (MAX_LENGTHS.keys + ['accent_color']).freeze

    def self.read(site)
      site.manifest.to_h.fetch(KEY, {}).to_h.slice(*FIELDS)
    end

    def self.accent(settings)
      color = settings.to_h['accent_color'].to_s
      color if color.match?(/\A#[0-9a-f]{6}\z/i)
    end

    def self.save!(site, input)
      values = input.to_h.stringify_keys.slice(*FIELDS).transform_values { |value| value.to_s.strip }
      valid_text = MAX_LENGTHS.all? { |field, length| values[field].to_s.length <= length }
      color = values['accent_color'].presence
      unless valid_text && (!color || color.match?(/\A#[0-9a-f]{6}\z/i))
        raise Invalid, 'Check the text lengths and choose a six-digit hex color.'
      end

      site.with_lock { site.update!(manifest: site.manifest.to_h.merge(KEY => values.compact_blank)) }
    end
  end
end
