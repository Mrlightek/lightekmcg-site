module LightekSessions
  module Presentation
    module_function
    def normalize!(attributes, previous = {})
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
      result['participants'] = values.fetch('participants', previous.fetch('participants',{})).to_h.first(50).to_h do |identity,raw|
        item = raw.to_h.stringify_keys
        effect = item.fetch('effect', 'clean')
        raise ArgumentError, 'Choose a supported camera effect.' unless %w[clean mono warm cool soft].include?(effect)
        prior=previous.fetch('participants',{}).fetch(identity,{})
        visible=item.fetch('visible',prior.fetch('visible',true))
        raise ArgumentError,'Program video visibility must be true or false.' unless [true,false].include?(visible)
        audio_gain=program_number(item.fetch('audio_gain',prior.fetch('audio_gain',1)),0,1)
        order=Integer(item.fetch('order',prior.fetch('order',0)).to_s,10)
        raise ArgumentError,'Program order must be between 0 and 49.' unless order.between?(0,49)
        [identity,{'visible'=>visible,'audio_gain'=>audio_gain,'order'=>order,'name'=>item['name'].to_s.first(80), 'role'=>item['role'].to_s.first(80),
          'effect'=>effect, 'mirror'=>ActiveModel::Type::Boolean.new.cast(item['mirror']),
          'fit'=>item['fit'] == 'cover' ? 'cover' : 'contain'}]
      end
      raise ArgumentError, 'Invalid participant identity.' unless result['participants'].keys.all? { |key| key.match?(/\Auser-\d+\z/) }
      result
    end
    def program_number(value,min,max)
      number=Float(value)
      raise ArgumentError,'Program audio level must be between 0 and 1.' unless number.finite? && number.between?(min,max)
      number
    rescue TypeError
      raise ArgumentError,'Choose a numeric program audio level.'
    end
  end
end
