# frozen_string_literal: true
module NevaehIntelligences
  module EditorialDirection
    module_function
    def apply(text:, notes:, context:)
      directives = {}; unsupported = []
      notes.to_s.lines.each do |line|
        line = line.strip
        next if line.empty?
        key, value = line.split(':', 2).map { |part| part.to_s.strip }
        case key.downcase
        when 'tone'
          %w[warm formal direct enthusiastic].include?(value.downcase) ? directives['tone'] = value.downcase : unsupported << line
        when 'max words'
          value.match?(/\A\d+\z/) && value.to_i.between?(10, 2000) ? directives['max_words'] = value.to_i : unsupported << line
        when 'opening', 'closing'
          if value.length.between?(1, 1000) && (value.scan(/\{([^{}]+)\}/).flatten - WritingEngine::TOKENS).empty?
            directives[key.downcase] = value.gsub(/\{([^{}]+)\}/) { context.fetch(Regexp.last_match(1)).strip }
          else
            unsupported << line
          end
        else
          unsupported << line
        end
      end
      result = text.dup
      case directives['tone']
      when 'formal'
        {"let's" => 'let us', "we're" => 'we are', "don't" => 'do not', "can't" => 'cannot'}.each { |from, to| result.gsub!(/\b#{Regexp.escape(from)}\b/i, to) }
      when 'warm' then result = "Together, #{result[0]&.downcase}#{result[1..]}" unless directives['opening']
      when 'direct' then result = result.sub(/\ALet's talk about /i, 'Focus: ')
      when 'enthusiastic' then result = result.sub(/\.(?=\s|\z)/, '!')
      end
      result = [directives['opening'], result, directives['closing']].compact.join("\n\n")
      if directives['max_words'] && result.split.length > directives['max_words']
        result = result.split.first(directives['max_words']).join(' ').sub(/[,:;]+\z/, '') + '…'
      end
      {text: result, applied: directives, unsupported: unsupported}
    end
  end
end
