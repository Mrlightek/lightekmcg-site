# frozen_string_literal: true
require 'json'
require 'digest'
module NevaehIntelligences
  module Neural
    # Native fixed-window neural language model. Position-specific embeddings,
    # tanh hidden units and softmax next-token probabilities; SGD updates weights.
    # No external inference process, HTTP provider or placeholder training step.
    class Network
      SPECIAL = %w[<unk> <bos> <sep> <eos>].freeze
      WINDOW = 4
      attr_reader :state
      def self.tokens(text)
        text.to_s.downcase.scan(/[\p{L}\p{N}]+(?:['’][\p{L}]+)?|[^\s\p{L}\p{N}]/).first(256)
      end
      def self.build(examples:, hidden_size: 16, vocabulary_limit: 256, seed: 17)
        counts = Hash.new(0)
        examples.each { |row| tokens(row.fetch('prompt') + ' ' + row.fetch('response')).each { |token| counts[token] += 1 } }
        vocabulary = SPECIAL + counts.sort_by { |word, count| [-count, word] }.first(vocabulary_limit - SPECIAL.length).map(&:first)
        random = Random.new(seed)
        h = hidden_size
        state = {'schema' => 1, 'window' => WINDOW, 'vocabulary' => vocabulary, 'hidden_size' => h,
          'embedding' => Array.new(vocabulary.length * (WINDOW + 1)) { Array.new(h) { (random.rand - 0.5) * 0.16 } },
          'output' => Array.new(vocabulary.length) { Array.new(h) { (random.rand - 0.5) * 0.16 } },
          'hidden_bias' => Array.new(h, 0.0), 'output_bias' => Array.new(vocabulary.length, 0.0), 'updates' => 0}
        new(state)
      end
      def initialize(state)
        @state = state
        validate!
        @vocabulary = state.fetch('vocabulary'); @index = @vocabulary.each_with_index.to_h
        @size = @vocabulary.length; @hidden = state.fetch('hidden_size')
      end
      def validate!
        s = @state; v = s['vocabulary']; h = s['hidden_size']
        raise ArgumentError, 'Invalid neural checkpoint dimensions' unless s['schema'] == 1 && s['window'] == WINDOW && v.is_a?(Array) && v.length.between?(5, 512) && v.first(4) == SPECIAL && v.uniq == v && v.all? { |token| token.is_a?(String) && token.length.between?(1, 100) } && h.is_a?(Integer) && h.between?(8, 32)
        {'embedding' => [v.length * (WINDOW + 1), h], 'output' => [v.length, h]}.each do |key, (rows, columns)|
          matrix = s[key]
          raise ArgumentError, 'Invalid neural checkpoint matrix' unless matrix.is_a?(Array) && matrix.length == rows && matrix.all? { |row| row.is_a?(Array) && row.length == columns && row.all? { |x| x.is_a?(Numeric) && x.finite? && x.abs <= 1000 } }
        end
        {'hidden_bias' => h, 'output_bias' => v.length}.each do |key, length|
          raise ArgumentError, 'Invalid neural checkpoint bias' unless s[key].is_a?(Array) && s[key].length == length && s[key].all? { |x| x.is_a?(Numeric) && x.finite? && x.abs <= 1000 }
        end
      end
      def encode(text) = self.class.tokens(text).map { |token| @index.fetch(token, 0) }
      def features(prompt, prefix)
        features = Hash.new(0.0)
        context = prompt.last(64)
        context.each { |id| features[id] += 0.7 / [context.length, 1].max }
        window = ([1] * WINDOW + prefix).last(WINDOW)
        window.each_with_index { |id, position| features[(position + 1) * @size + id] += 1.0 }
        features
      end
      def forward(features)
        hidden = @state['hidden_bias'].dup
        features.each do |id, scale|
          row = @state['embedding'][id]
          @hidden.times { |j| hidden[j] += row[j] * scale }
        end
        hidden.map! { |value| Math.tanh(value) }
        logits = @state['output_bias'].dup
        @state['output'].each_with_index do |row, i|
          total = logits[i]
          @hidden.times { |j| total += row[j] * hidden[j] }
          logits[i] = total
        end
        maximum = logits.max
        probabilities = logits.map { |value| Math.exp(value - maximum) }
        sum = probabilities.sum
        probabilities.map! { |value| value / sum }
        [hidden, probabilities]
      end
      def step(prompt:, prefix:, target:, learning_rate:)
        input = features(prompt, prefix)
        hidden, probability = forward(input)
        loss = -Math.log([probability[target], 1e-12].max)
        return loss unless learning_rate
        gradient = probability.dup; gradient[target] -= 1.0
        dh = Array.new(@hidden, 0.0)
        @size.times do |i|
          row = @state['output'][i]; delta = gradient[i]
          @hidden.times do |j|
            dh[j] += row[j] * delta
            row[j] -= learning_rate * delta * hidden[j]
          end
          @state['output_bias'][i] -= learning_rate * delta
        end
        @hidden.times { |j| dh[j] = [[dh[j] * (1.0 - hidden[j]**2), -2.0].max, 2.0].min }
        input.each { |id, scale| @hidden.times { |j| @state['embedding'][id][j] -= learning_rate * dh[j] * scale } }
        @hidden.times { |j| @state['hidden_bias'][j] -= learning_rate * dh[j] }
        @state['updates'] += 1
        loss
      end
      def epoch(examples, learning_rate: nil, seed: 0)
        loss = 0.0; count = 0
        rows = learning_rate ? examples.shuffle(random: Random.new(seed)) : examples
        rows.each do |row|
          prompt = encode(row.fetch('prompt')); response = encode(row.fetch('response')).first(64) + [3]; prefix = [2]
          response.each do |target|
            loss += step(prompt: prompt, prefix: prefix, target: target, learning_rate: learning_rate)
            prefix << target; count += 1
          end
        end
        loss / [count, 1].max
      end
      def generate(prompt:, max_tokens: 64, temperature: 0.6, seed: 17)
        raise ArgumentError, 'Prompt must contain 1–8000 characters' unless prompt.is_a?(String) && prompt.strip.length.between?(1, 8000)
        raise ArgumentError, 'Choose 1–100 output tokens and temperature 0–1.5' unless max_tokens.is_a?(Integer) && max_tokens.between?(1, 100) && temperature.is_a?(Numeric) && temperature.between?(0, 1.5)
        ids = encode(prompt); prefix = [2]; generated = []; random = Random.new(seed)
        max_tokens.times do
          _, probabilities = forward(features(ids, prefix))
          choices = probabilities.each_with_index.reject { |_p, id| id < 3 }.sort_by { |p, _id| -p }.first(8)
          token = if temperature.zero?
            choices.first.last
          else
            scores = choices.map { |p, id| [p**(1.0 / temperature), id] }; threshold = random.rand * scores.sum(&:first)
            selected = scores.last.last
            scores.each { |score, id| threshold -= score; if threshold <= 0; selected = id; break; end }
            selected
          end
          break if token == 3
          generated << @vocabulary[token]; prefix << token
        end
        text = generated.join(' ').gsub(/\s+([,.!?;:])/, '\\1').gsub(/([(\[])[ ]+/, '\\1')
        text = text.sub(/\A\p{L}/) { |letter| letter.upcase }
        {'text' => text, 'tokens' => generated.length, 'engine' => 'native_neural', 'checkpoint_sha256' => Digest::SHA256.hexdigest(CanonicalJson.dump(@state))}
      end
    end
  end
end
