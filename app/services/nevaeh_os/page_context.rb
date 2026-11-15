# frozen_string_literal: true
require 'uri'
module NevaehOs
  module PageContext
    # Read-only navigation context never grants authority to execute a page's actions.
    AREAS=[
      ['studio',/studio|production|broadcast|live-broadcast|session-media/,'Studio & production','studio',%w[studio marketing],%w[producer cast_director blocking editor publisher media],'docs/studio/'],
      ['growth',/growth|campaign|website.audit/,'Growth & campaigns','growth',%w[growth marketing sales],%w[growth campaign sales],'docs/sales/'],
      ['payroll',/payroll/,'Payroll','platform',%w[payroll hr],%w[payroll finance],'docs/'],
      ['finance',/bank|accounting|payout|billing|invoice|payment|ledger|susu/,'Finance & accounting','platform',%w[bank accounting susu dymond],%w[finance],'docs/'],
      ['mail',/mail|message/,'Mail & messaging','platform',%w[mail messages],%w[mail],'docs/mail/'],
      ['commerce',/commerce|order|shipping|inventory|catalog|marketplace/,'Commerce & fulfillment','platform',%w[commerce shipping catalog orders ecommerce],%w[commerce],'docs/'],
      ['people',/people|payroll|employee|directory|onboard|offboard|department/,'People & directory','platform',%w[people directory hr payroll],%w[people payroll],'docs/'],
      ['hosting',/server|application|deployment|domain|dns|hosting/,'Servers, applications & domains','ubuntu',%w[hosting server deployment dns domains ubuntu applications],%w[hosting ubuntu],'docs/server'],
      ['sales',/sales|crm|lead|contact|opportunit/,'Sales & CRM','growth',%w[sales crm growth],%w[sales growth],'docs/sales/'],
      ['website',/website|design|page|content/,'Websites & content','platform',%w[site website cms],%w[website muse],'docs/'],
      ['support',/ticket|support|helpdesk/,'Support & tickets','agents',%w[ticket],%w[support],'docs/nevaeh/'],
      ['nevaeh',/nevaeh|software.library/,'Nevaeh workforce & learning','director_stage',%w[nevaeh factory agents],%w[librarian language_tester trainer capability_builder warden],'docs/nevaeh/'],
      ['community',/communit|social/,'Community & social','platform',%w[community social messages],%w[mail publisher],'docs/'],
      ['reservations',/reservation|room|booking/,'Reservations & rooms','platform',%w[reservation rooms studio],%w[support producer],'docs/'],
      ['compliance',/legal|compliance/,'Legal & compliance','platform',%w[legal compliance],%w[compliance],'docs/']
    ].freeze
    module_function
    def normalize(value)
      return nil unless value.is_a?(Hash)
      raw=value.deep_stringify_keys
      location=raw.fetch('path','').to_s+raw.fetch('search','').to_s
      raise ArgumentError,'Page context is too long' if location.bytesize>4096
      uri=URI.parse(location)
      raise ArgumentError,'Use a local application page as context' unless uri.scheme.nil? && uri.host.nil? && uri.fragment.nil? && uri.path.match?(/\A\/(?:dashboard|employee)(?:\/[a-zA-Z0-9_-]+)*\/?\z/)
      query=URI.decode_www_form(uri.query.to_s).select { |key,val| %w[site_id scene_id project_id].include?(key) && val.match?(/\A[1-9][0-9]{0,17}\z/) }.to_h
      {'path'=>uri.path,'title'=>raw['title'].to_s.first(160)}.merge(query)
    rescue URI::InvalidURIError
      raise ArgumentError,'Use a local application page as context'
    end
    def area(context)
      path=context.fetch('path').sub(%r{\A/(dashboard|employee)/?},'')
      AREAS.find { |row| path.match?(row[1]) } || ['dashboard',/.*/,'Dashboard','start',[],%w[nevaeh],'docs/nevaeh/']
    end
    def catalog(actor,context)
      info=area(context)
      Guide.catalog(actor:actor).select { |row| info[4].any? { |domain| row[:key].start_with?(domain+'.') } }
    end
    def help(actor,context,query:nil)
      info=area(context);entries=catalog(actor,context);connected=entries.select { |row| row[:availability]=='connected' }
      topic=Guide.topics(actor:actor).find { |row| row[:id]==info[3] }&.fetch(:id) || 'commands'
      tutorial=Guide.tutorial(topic,actor:actor)
      docs=[]
      if Guide.allowed?('admin',actor)
        words=(info[0]+' '+query.to_s).downcase.scan(/[a-z][a-z0-9_]{2,}/).uniq.first(14)
        docs=NevaehIntelligences::SoftwareLibrary.new.documents.map do |doc|
          score=words.count { |word| (doc[:path]+' '+doc[:title]).downcase.include?(word) }*3+words.count { |word| doc[:body].downcase.include?(word) }
          score+=2 if doc[:path].start_with?(info[6])
          [score,doc]
        end.select { |score,_| score>2 }.sort_by { |score,doc| [-score,doc[:path]] }.first(3).map(&:last)
      end
      terms=query.to_s.downcase.scan(/[a-z][a-z0-9_]{2,}/)-%w[this that page here what when where have with help you can why how the and from]
      sources=docs.map do |doc|
        lines=doc[:body].lines
        index=lines.index { |line| terms.any? { |term| line.downcase.include?(term) } } || 0
        {title:doc[:title],path:doc[:path],sha256:doc[:sha256],excerpt:lines[[index-2,0].max,14].join.first(1000)}
      end
      summary="You're in #{info[2]}. I can help with this page's documented workflows and delegate connected tasks to the workforce."
      summary+="\n\n#{sources.map { |source| source[:title]+"\n"+source[:excerpt] }.join("\n\n")}" if sources.any?
      summary+="\n\nDirect task connections are still needed for this area. The page's controls remain available; the capability audit can record the missing connections." if connected.empty?
      {page:context.slice('path','title','site_id','scene_id','project_id').merge('area'=>info[2]),text:summary,guide_url:"/dashboard/nevaeh/guide?topic=#{topic}",sources:sources,
        actions:connected.first(12).map { |row| {key:row[:key],title:row[:title],example:row[:example],inputs:row[:inputs]} },specialists:info[5].filter_map { |key| role=Workforce::ROLES[key];role && {key:key,name:role[0],purpose:role[2]} },missing_connections:entries.count { |row| row[:availability]!='connected' }}
    end
    def coverage(actor,catalog:nil)
      entries=catalog || Guide.catalog(actor:actor)
      AREAS.map do |row|
        relevant=entries.select { |entry| row[4].any? { |domain| entry[:key].start_with?(domain+'.') } }
        {area:row[2],connected:relevant.count { |entry| entry[:availability]=='connected' },missing:relevant.count { |entry| entry[:availability]!='connected' },specialists:row[5]}
      end
    end
    def question?(text) = text.is_a?(String) && text.strip.match?(/\A(?:help(?: me)?(?: (?:here|with this page))?|what (?:can you do|can i do|is this|should i do)(?: (?:here|on this page|next))?|explain (?:this|this page)|how (?:do i|does this|can you)\b.*)[?!.]?\z/i)
  end
end
