# frozen_string_literal: true
require 'digest'
module NevaehOs
  # One finite action vocabulary for phrases, model proposals, plans and teaching.
  module TaskCatalog
    REVIEWS={
      'website'=>[%w[website web page content],%w[audit findings issues]],
      'sales'=>[%w[sales lead leads deal deals crm],%w[followup followups overdue pipeline]],
      'finance'=>[%w[accounting finance transaction transactions bookkeeping],%w[uncategorized unclassified categorize classification]],
      'payroll'=>[%w[payroll payrun payruns],%w[review check due drafts approval]],
      'commerce'=>[%w[order orders commerce fulfillment],%w[paid unfulfilled fulfillment awaiting]],
      'people'=>[%w[onboarding offboarding employee employees people],%w[open unfinished review check]],
      'hosting'=>[%w[server servers hosting infrastructure],%w[health status unhealthy review check]],
      'compliance'=>[%w[compliance jurisdiction monitor monitors legal],%w[stale failed freshness review check]]
    }.freeze
    module_function
    def keys = %w[website_page campaign]+REVIEWS.keys.map { |key| "#{key}_review" }
    def role(key) = key=='website_page' ? 'website' : key=='campaign' ? 'campaign' : key.delete_suffix('_review')
    def title(key)
      return 'Create a draft website page' if key=='website_page'
      return 'Create a campaign draft and private preview' if key=='campaign'
      SpecialistTasks::DEFINITIONS.fetch(role(key))[0]
    end
    def fields(key)
      case key
      when 'website_page' then {'site_id'=>'integer','title'=>'string','slug'=>'optional_string'}
      when 'campaign' then {'site_id'=>'integer','service'=>'string','tone'=>'tone'}
      else
        field=SpecialistTasks::DEFINITIONS.fetch(role(key))[1]
        field ? {field=>'integer'} : {}
      end
    end
    def fingerprint
      Digest::SHA256.hexdigest([File.read(__FILE__),File.read(Rails.root.join('docs/nevaeh/tutorials/ten_tasks.md')),File.read(Rails.root.join('app/services/nevaeh_intelligences/neural/task_head.rb'))].join("\n"))
    end
    def normalize(text) = text.downcase.strip.gsub(/[?!.]+\z/,'').gsub(/\s+/,' ')
    def phrase_digest(text) = Digest::SHA256.hexdigest(normalize(text))
    def match(text)
      return [] if text.match?(/\A(?:how\b|what\b|why\b|explain\b)|\b(?:don't|do not|never|avoid|not)\b/i)
      clean=normalize(text).sub(/\A(?:(?:can|could|would) you (?:please )?|please |i(?:'d| would) like (?:you )?to |i want (?:you )?to )/,'')
      clean=clean.gsub(/\bwebpages?\b/,'website page').sub(/\Aadvertise /,'create ad for ').sub(/\Apromote /,'create campaign ad promoting ').sub(/\Ai need (?:an? )?/,'create ')
      clean=clean.sub(/\A(?:set up|put together) /,'create ').sub(/\A(?:have a look at|look over) /,'review ').sub(/\Alook for /,'find ')
      return [] unless clean.match?(/\A(?:create|add|make|build|new|produce|draft|prepare|review|check|inspect|audit|find|show|list)\b/)
      words=clean.scan(/[a-z]+/)
      return ['website_page'] if words.intersect?(%w[create add make build new draft prepare]) && words.include?('page')
      return ['campaign'] if words.intersect?(%w[create make produce build draft prepare]) && words.intersect?(%w[campaign ad advert advertisement promo])
      REVIEWS.filter_map do |key,(subjects,actions)|
        "#{key}_review" if words.intersect?(subjects) && words.intersect?(actions+%w[review check inspect audit]+(key=='people' ? %w[onboarding offboarding] : []))
      end
    end
    def clauses(text)
      # Quoted titles/briefs remain literal, even if they contain a conjunction.
      parts=text.scan(/"[^"\n]*"|[^"]+/)
      groups=['']
      parts.each do |part|
        if part.start_with?('"',"'")
          groups[-1]+=part
        else
          chunks=part.split(/\s*(?:;|\n|\band then\b|\bthen\b|\band (?=(?:create|add|make|produce|review|check|find|show|list)\b))\s*/i)
          groups[-1]+=chunks.shift.to_s
          groups.concat(chunks)
        end
      end
      groups.map(&:strip).reject(&:empty?)
    end
    def extract(key,text)
      data={}
      %w[site employer].each do |scope|
        match=text.match(/\b#{scope}(?:_id| id)?\s*[:#]?\s*([1-9][0-9]{0,17})\b/i) || (scope=='site' && text.match(/\bwebsite\s*#?\s*([1-9][0-9]{0,17})\b/i))
        data["#{scope}_id"]=match[1].to_i if match && fields(key).key?("#{scope}_id")
      end
      body=text.sub(/\s+(?:on|for) (?:web)?site(?: id)?\s*#?\s*\d+\s*\z/i,'').strip
      if key=='website_page'
        named=body.match(/\b(?:called|named|titled|name it)\s+(.+)\z/i)
        data['title']=literal(named[1]) if named
      elsif key=='campaign'
        promoted=body.match(/\b(?:promoting|advertising|for)\s+(.+)\z/i) || body.match(/\A(?:advertise|promote)\s+(.+)\z/i)
        data['service']=literal(promoted[1]) if promoted
        data['tone']=body.match?(/\bprofessional\b/i) ? 'professional' : 'funny'
      end
      data
    end
    def literal(text)
      value=text.strip
      quoted=(value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
      quoted ? value[1...-1] : value.sub(/[.!?]+\z/,'')
    end
    def validate!(key,inputs,partial:false)
      raise ArgumentError,'Choose one of the ten supported tasks' unless keys.include?(key)
      schema=fields(key)
      raise ArgumentError,'Use only the named task inputs' unless inputs.is_a?(Hash) && (inputs.keys-schema.keys).empty?
      inputs.each do |field,value|
        type=schema.fetch(field)
        good=if type=='integer'
          value.is_a?(Integer) && value.positive? && value<=999999999999999999
        elsif type=='tone'
          %w[funny professional].include?(value)
        else
          value.is_a?(String) && value.strip.length.between?(1,field=='service' ? 80 : 160) && !value.match?(/[\x00-\x1f\x7f]/)
        end
        raise ArgumentError,"Invalid #{field.humanize.downcase}" unless good
      end
      missing=schema.keys.reject { |field| schema[field]=='optional_string' || inputs.key?(field) }
      raise ArgumentError,"Provide #{missing.join(', ')}" if !partial && missing.any?
      missing
    end
    def command(key,inputs)
      inputs=inputs.deep_dup
      validate!(key,inputs)
      command=case key
      when 'website_page' then {'kind'=>'website_page','site_id'=>inputs.fetch('site_id'),'values'=>inputs.except('site_id')}
      when 'campaign' then {'kind'=>'campaign_produce','operation'=>'start','site_id'=>inputs.fetch('site_id'),'values'=>inputs.except('site_id')}
      else {'kind'=>'specialist_review','role'=>role(key),'inputs'=>inputs}
      end
      command.merge('task_contract'=>{'key'=>key,'catalog_sha256'=>fingerprint})
    end
    def guard!(command)
      stamp=command['task_contract'];return unless stamp
      raise ArgumentError,'Use a valid task contract stamp' unless stamp.is_a?(Hash) && stamp.keys.sort==%w[catalog_sha256 key]
      raise ArgumentError,'The task catalog changed; prepare a fresh request' unless stamp['catalog_sha256']==fingerprint && keys.include?(stamp['key'])
      key=stamp['key']
      expected=key=='website_page' ? 'site.page.create' : key=='campaign' ? 'marketing.campaign.produce' : SpecialistTasks.capability(role(key))
      raise ArgumentError,'The planned task changed' unless Agents.capability(command)==expected
    end
    def manifest = keys.map { |key| {key:key,title:title(key),fields:fields(key)} }
  end
end
