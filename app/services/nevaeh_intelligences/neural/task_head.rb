# frozen_string_literal: true
module NevaehIntelligences
  module Neural
    # Small learned softmax intent head; vocabulary/IDF and weights come from the
    # reviewed corpus. Lexical normalization shares common English domain terms.
    class TaskHead
      GROUPS={
        'create'=>%w[create add make build new draft prepare produce],
        'review'=>%w[review check inspect audit find show list assess examine],
        'website'=>%w[website web site webpage],
        'campaign'=>%w[campaign ad advert advertisement advertising promo promote tiktok],
        'sales'=>%w[sales lead leads deal deals crm opportunity opportunities],
        'finance'=>%w[finance accounting transaction transactions bookkeeping],
        'payroll'=>%w[payroll payrun payruns wages],
        'commerce'=>%w[commerce order orders fulfillment fulfilment unfulfilled],
        'people'=>%w[people employee employees onboarding offboarding],
        'hosting'=>%w[hosting server servers infrastructure],
        'compliance'=>%w[compliance legal jurisdiction monitor monitors]
      }.freeze
      STOP=%w[a an the i me my our your please can could would you to for of on at in is are do with].freeze
      attr_reader :state
      def self.tokens(text)
        synonyms=GROUPS.flat_map { |canonical,words| words.map { |word| [word,canonical] } }.to_h
        text.downcase.scan(/[\p{L}\p{N}]+/).first(128).reject { |word| STOP.include?(word) }.map { |word| synonyms.fetch(word,word) }.uniq
      end
      def self.build(examples:,labels:)
        documents=examples.map { |row| tokens(row.fetch('prompt')) }
        counts=documents.flatten.tally
        vocabulary=counts.sort_by { |word,count| [-count,word] }.first(512).map(&:first)
        idf=vocabulary.map { |word| 1+Math.log((documents.size+1).fdiv(counts.fetch(word)+1)) }
        new({'schema'=>1,'labels'=>labels,'vocabulary'=>vocabulary,'idf'=>idf,
          'weights'=>Array.new(labels.size) { Array.new(vocabulary.size,0.0) },'bias'=>Array.new(labels.size,0.0),'updates'=>0})
      end
      def initialize(state)
        @state=state;labels=state['labels'];vocabulary=state['vocabulary']
        valid=state.keys.sort==%w[bias idf labels schema updates vocabulary weights] && state['schema']==1 && labels.is_a?(Array) && labels.size.between?(2,12) && labels.uniq==labels && labels.all? { |key| key.is_a?(String) && key.match?(/\A[a-z_]{1,40}\z/) } && vocabulary.is_a?(Array) && vocabulary.size.between?(1,512) && vocabulary.uniq==vocabulary && vocabulary.all? { |word| word.is_a?(String) && word.length.between?(1,100) }
        raise ArgumentError,'Invalid local task head dimensions' unless valid
        raise ArgumentError,'Invalid local task weights' unless state['weights'].is_a?(Array) && state['weights'].size==labels.size && state['weights'].all? { |row| row.is_a?(Array) && row.size==vocabulary.size && row.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=1000 } }
        raise ArgumentError,'Invalid local task bias' unless state['bias'].is_a?(Array) && state['bias'].size==labels.size && state['bias'].all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=1000 }
        raise ArgumentError,'Invalid local task vocabulary weights' unless state['idf'].is_a?(Array) && state['idf'].size==vocabulary.size && state['idf'].all? { |v| v.is_a?(Numeric) && v.finite? && v.between?(0.1,16) } && state['updates'].is_a?(Integer) && state['updates']>=0
        @index=vocabulary.each_with_index.to_h
      end
      def features(text)
        values=self.class.tokens(text).filter_map { |word| id=@index[word];[id,state['idf'][id]] if id }.to_h
        length=Math.sqrt(values.values.sum { |value| value*value })
        values.transform_values { |value| value/[length,1].max }
      end
      def probabilities(features)
        logits=state['weights'].each_with_index.map { |weights,index| state['bias'][index]+features.sum { |id,value| weights[id]*value } }
        maximum=logits.max;values=logits.map { |value| Math.exp(value-maximum) };total=values.sum
        values.map { |value| value/total }
      end
      def epoch(examples,learning_rate:nil,seed:0)
        rows=learning_rate ? examples.shuffle(random:Random.new(seed)) : examples
        total=rows.sum do |example|
          values=features(example.fetch('prompt'));probabilities=probabilities(values);target=state['labels'].index(example.fetch('response'))
          raise ArgumentError,'Unknown local task training label' unless target
          loss=-Math.log([probabilities[target],1e-12].max)
          if learning_rate
            probabilities.each_with_index do |probability,index|
              gradient=probability-(index==target ? 1 : 0)
              values.each { |id,value| state['weights'][index][id]-=learning_rate*(gradient*value+0.0001*state['weights'][index][id]) }
              state['bias'][index]-=learning_rate*gradient
            end
            state['updates']+=1
          end
          loss
        end
        total/[rows.size,1].max
      end
      def rank(prompt,labels)
        raise ArgumentError,'Task labels do not match this checkpoint' unless labels.sort==state['labels'].sort
        probabilities(features(prompt)).each_with_index.map { |probability,index| {'label'=>state['labels'][index],'confidence'=>probability.round(5),'score'=>Math.log([probability,1e-12].max)} }.sort_by { |row| [-row['confidence'],row['label']] }
      end
    end
  end
end
