# frozen_string_literal: true
require 'date'
module Studio
  module Director
    # Optional fiction prompts, never a factual inference about real people.
    class Personality
      TEMPLATES={
        'aries'=>['Pioneer','decisive','impatient','acts before asking'],
        'taurus'=>['Builder','steadfast','resistant to change','protects a routine'],
        'gemini'=>['Messenger','curious','scattered','asks a second question'],
        'cancer'=>['Guardian','nurturing','guarded','checks who might be hurt'],
        'leo'=>['Performer','generous','proud','makes a public gesture'],
        'virgo'=>['Analyst','precise','perfectionist','notices the overlooked detail'],
        'libra'=>['Mediator','fair-minded','indecisive','hears both sides'],
        'scorpio'=>['Investigator','resourceful','suspicious','looks beneath the explanation'],
        'sagittarius'=>['Explorer','hopeful','reckless','imagines a wider possibility'],
        'capricorn'=>['Architect','disciplined','controlling','sets a measurable plan'],
        'aquarius'=>['Visionary','inventive','detached','questions the usual approach'],
        'pisces'=>['Dreamer','empathetic','avoidant','notices an unspoken feeling']
      }.freeze
      def self.catalog
        TEMPLATES.flat_map do |key,(name,strength,flaw,habit)|
          %w[balanced pressure growth].map { |mode| {'key'=>"#{key}:#{mode}",'name'=>"#{name} · #{mode}",'strength'=>strength,'tension'=>flaw,'habit'=>habit,'creative_reference'=>'zodiac-inspired fiction template'} }
        end
      end
      def self.from_date(value)
        date=Date.iso8601(value)
        boundaries=[[120,'aquarius'],[219,'pisces'],[321,'aries'],[420,'taurus'],[521,'gemini'],[621,'cancer'],[723,'leo'],[823,'virgo'],[923,'libra'],[1023,'scorpio'],[1122,'sagittarius'],[1222,'capricorn']]
        marker=date.month*100+date.day
        (boundaries.reverse.find { |first,_| marker>=first } || [0,'capricorn']).last
      rescue Date::Error,TypeError
        raise ArgumentError,'Use an ISO birth date for a fictional character, or select a personality template'
      end
      def self.character(raw)
        raise ArgumentError,'Character inputs must be an object' unless raw.is_a?(Hash) && (raw.keys-%w[id name template birth_date birth_time birth_place goal knows secret]).empty?
        id=raw.fetch('id').to_s;name=raw.fetch('name').to_s;goal=raw.fetch('goal').to_s
        raise ArgumentError,'Use a stable character ID, name and goal' unless id.match?(/\A[a-zA-Z0-9_-]{1,60}\z/) && name.length.between?(1,80) && goal.length.between?(1,400)
        time=raw['birth_time'];place=raw['birth_place']
        raise ArgumentError,'Use a fictional birth time in HH:MM form' if time && (!time.is_a?(String) || !time.match?(/\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\z/))
        raise ArgumentError,'Use a fictional origin of at most 160 characters' if place && (!place.is_a?(String) || place.length>160)
        key=raw['template'] || "#{from_date(raw.fetch('birth_date'))}:balanced"
        template=catalog.find { |row| row['key']==key } || raise(ArgumentError,'Choose a personality template from /produce personalities')
        knows=raw.fetch('knows',[])
        raise ArgumentError,'Give each character at most 32 known facts of 400 characters' unless knows.is_a?(Array) && knows.size<=32 && knows.all? { |fact| fact.is_a?(String) && fact.length.between?(1,400) }
        secret=raw.fetch('secret','').to_s
        raise ArgumentError,'Keep a private character secret within 400 characters' if secret.length>400
        {'id'=>id,'name'=>name,'goal'=>goal,'personality'=>template,'knows'=>knows.uniq,'secret'=>secret,'fictional_birth_date'=>raw['birth_date'],'fictional_birth_time'=>time,'fictional_birth_place'=>place}.compact
      end
    end
  end
end
