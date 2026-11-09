module LightekSessions
  module Presentation
    module_function
    def normalize!(attributes)
      values = attributes.to_h.stringify_keys
      layout = values.fetch('layout', 'gallery')
      raise ArgumentError, 'Choose a presentation layout.' unless %w[gallery presenter split fullscreen].include?(layout)
      result = {'layout'=>layout}
      %w[title subtitle ticker brand].each { |key| result[key] = values[key].to_s.first(key == 'ticker' ? 300 : 120) }
      %w[background accent].each do |key|
        color = values.fetch(key, key == 'accent' ? '#d6edac' : '#142f2c')
        raise ArgumentError, 'Use a six-digit color.' unless color.to_s.match?(/\A#[a-fA-F0-9]{6}\z/)
        result[key] = color
      end
      featured = values['featured'].to_s
      raise ArgumentError, 'Choose a session participant.' unless featured.empty? || featured.match?(/\Auser-\d+\z/)
      result['featured'] = featured
      result['participants'] = values.fetch('participants', {}).to_h.first(50).to_h.transform_values do |raw|
        item = raw.to_h.stringify_keys
        effect = item.fetch('effect', 'clean')
        raise ArgumentError, 'Choose a supported camera effect.' unless %w[clean mono warm cool soft].include?(effect)
        {'name'=>item['name'].to_s.first(80), 'role'=>item['role'].to_s.first(80),
          'effect'=>effect, 'mirror'=>ActiveModel::Type::Boolean.new.cast(item['mirror']),
          'fit'=>item['fit'] == 'cover' ? 'cover' : 'contain'}
      end
      raise ArgumentError, 'Invalid participant identity.' unless result['participants'].keys.all? { |key| key.match?(/\Auser-\d+\z/) }
      result
    end
  end
end
