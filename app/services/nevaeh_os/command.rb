# frozen_string_literal: true
require 'json'
module NevaehOs
  module Command
    HELP = <<~TEXT.freeze
      I'm Nevaeh. Tell me what you need, or use a command:
      /guide — open the operating manual and tutorials
      /describe susu.list — inputs, permissions, examples and verification
      /watch create {"name":"FFmpeg updates","kind":"ubuntu_package","target":{"package":"ffmpeg"},"response":"prepare"}
      /watch list · /watch show ID · /watch poll ID · /watch pause ID · /watch resume ID
      /watch apply EVENT_ID — apply a prepared event response
      /agents — agents, assigned workers and execution status
      /delegate sage susu.list — assign a real task to Sage
      /agent schedule warden 60 susu.list — run every 60 minutes
      /agent run ID · /agent pause ID — control an agent worker
      susu.list — execute a capability directly; JSON inputs are optional
      show my susus — list the Susus you organize or belong to
      /models · /schema User — discover the installed Rails data model
      User.where(role: "client").limit(10) — Ruby-style data console; /rails also works
      /ubuntu search video · /ubuntu show ffmpeg · /ubuntu plan ffmpeg
      /ubuntu setup ffmpeg — install, document and connect a supported application
      /ubuntu install ffmpeg · /ubuntu docs ffmpeg · /ubuntu integrate ffmpeg
      /app describe ffmpeg · /app activate ffmpeg · /app run ffmpeg version
      /resources — available resource contracts and editable fields
      /capabilities — installed platform actions
      /read workers [ID] · /create workers {"name":"…","sections":[…]}
      /update workers ID {"lock_version":0,"status":"paused"} · /delete workers ID
      /execute INTENT {"field":"value"} — invoke a published intelligence
      /build ID — build and verify a construction
      /activate ID — activate a verified construction release
      /approve ID — approve a reviewed training dataset
      /train MODEL_ID {"dataset_id":1,"epochs":10} — train a native checkpoint
      /checkpoint ID — activate a verified language checkpoint
      /model ID your message — request a native neural draft
      /write caption {"topic":"Opening night"} — use the shared Studio writing engine
      /run ID — run an active worker through its ticket pipeline
      /learn https://docs.blender.org/… — import a training page as a draft
      /review ID — review an imported source and create a training dataset draft
      /search Blender — search software documentation and reviewed sources
      /produce catalog · /produce {"site_id":123,"name":"Episode 1","template_key":"comedy"} — reuse production recipes and show bibles
      /produce status ID · /produce retry VOICE_OPERATION_ID
      /campaign {"site_id":123,"service":"Xyzzy","tone":"funny"} — build an editable TikTok draft and private preview
      /campaign status ID · /campaign retry ID — production progress and recovery
      /growth SITE_ID — prepare or open today’s business growth plan
      /status — your recent actions · /briefing — today's operational briefing
      /remember Preferences: I prefer concise replies — offers a memory for consent
      /forget ID — remove one of your memories
      Ordinary phrases such as “list workers”, “pause worker 12”, and “create ticket {…}” also work. Ambiguous instructions need clarification. Action receipts remain in the audit log; personal memories require your consent.
    TEXT
    ALIASES = {'worker'=>'workers','ticket'=>'tickets','agent'=>'agents','source'=>'sources','dataset'=>'datasets','construction'=>'constructions','model'=>'language_models','profile'=>'writing_profiles'}.freeze
    module_function
    def parse(text)
      raise ArgumentError, 'Message must contain 1–4000 characters' unless text.is_a?(String) && text.strip.length.between?(1,4000)
      q = text.strip
      return {'kind'=>'production','operation'=>'catalog'} if q.match?(/\A\/?produce\s+catalog\z/i)
      if (m=q.match(/\A\/?produce\s+(status|retry)\s+([1-9][0-9]*)\z/i))
        return {'kind'=>'production','operation'=>m[1].downcase,'id'=>m[2].to_i}
      end
      if (m=q.match(/\A\/?produce\s+(\{.*\})\z/im))
        payload=JSON.parse(m[1])
        raise ArgumentError, 'Production input must be an object' unless payload.is_a?(Hash)
        return {'kind'=>'production','operation'=>'start','site_id'=>payload.delete('site_id'),'values'=>payload}.compact
      end
      if (m=q.match(/\A(?:please )?(?:make|create|produce)(?: me)? (?:a |an )?(22|42|48)[ -]minute (comedy|procedural|drama) episode (?:called|named) (.+)\z/i))
        durations={'comedy'=>'22','procedural'=>'42','drama'=>'48'}
        raise ArgumentError, 'Choose 22-minute comedy, 42-minute procedural or 48-minute drama, or choose a template with /produce catalog' unless durations[m[2].downcase]==m[1]
        return {'kind'=>'production','operation'=>'start','values'=>{'name'=>m[3].strip,'template_key'=>m[2].downcase}}
      end
      if (m=q.match(/\A\/?campaign\s+(status|retry)\s+([1-9][0-9]*)\z/i))
        return {'kind'=>'campaign_produce','operation'=>m[1].downcase,'id'=>m[2].to_i}
      end
      if (m=q.match(/\A\/?campaign\s+(\{.*\})\z/im))
        payload=JSON.parse(m[1])
        raise ArgumentError, 'Campaign input must be an object' unless payload.is_a?(Hash)
        return {'kind'=>'campaign_produce','operation'=>'start','site_id'=>payload.delete('site_id'),'values'=>payload}.compact
      end
      if (m=q.match(/\A(?:please )?(?:make|create|produce)(?: me)? (?:a |an )?(?:(funny|professional) )?(?:tiktok|tik tok) (?:campaign(?: ad)?|ad) (?:promoting|for) (.+?)[.!]?\z/i))
        return {'kind'=>'campaign_produce','operation'=>'start','values'=>{'service'=>m[2].strip,'tone'=>m[1]&.downcase || 'funny'}}
      end
      if (m=q.match(/\A(?:\/?growth|(?:prepare|show) (?:my )?growth plan)\s+([1-9][0-9]*)\z/i))
        return {'kind'=>'growth_plan','site_id'=>m[1].to_i}
      end
      if (m=q.match(/\A\/?(?:guide|tutorial)(?:\s+([a-z0-9_-]+))?\z/i))
        return {'kind'=>'guide','topic'=>m[1] || 'start'}
      end
      if (m=q.match(/\A\/?describe\s+([a-zA-Z0-9_.-]+)\z/))
        return {'kind'=>'describe','capability'=>m[1]}
      end
      if (m=q.match(/\A\/?(?:watch|watcher)\.(create|list|show|poll|pause|resume|apply)(?:\s+(\{.*\}))?\z/m))
        payload=m[2] ? JSON.parse(m[2]) : {}
        if m[1]=='create'
          return {'kind'=>'watch','operation'=>'create','attributes'=>payload}
        end
        raise ArgumentError,'Watcher action accepts an id field only' unless payload.is_a?(Hash) && (payload.keys-%w[id]).empty?
        raise ArgumentError,'Provide a positive watcher/event id' unless m[1]=='list' || payload['id'].to_s.match?(/\A[1-9][0-9]*\z/)
        return {'kind'=>'watch','operation'=>m[1],'id'=>payload['id']}.compact
      end
      if (m=q.match(/\A\/?watch\s+create\s+(\{.*\})\z/im))
        return {'kind'=>'watch','operation'=>'create','attributes'=>JSON.parse(m[1])}
      end
      if (m=q.match(/\A\/?watch\s+(show|poll|pause|resume|apply)\s+(\d+)\z/i))
        return {'kind'=>'watch','operation'=>m[1].downcase,'id'=>m[2].to_i}
      end
      if q.match?(/\A\/?watch(?:\s+list)?\z/i)
        return {'kind'=>'watch','operation'=>'list'}
      end
      if (m=q.match(/\A\/?delegate\s+(\S+)\s+(.+)\z/im))
        return {'kind'=>'agent_task','agent_ref'=>m[1],'instruction'=>m[2]}
      end
      if (m=q.match(/\A\/?agent\s+schedule\s+(\S+)\s+(\d+)\s+(.+)\z/im))
        return {'kind'=>'agent_task','agent_ref'=>m[1],'interval_minutes'=>m[2].to_i,'instruction'=>m[3]}
      end
      if (m=q.match(/\A\/?agent\s+(run|pause)\s+(\d+)\z/i))
        return {'kind'=>'agent_control','operation'=>m[1].downcase,'id'=>m[2].to_i}
      end
      if q.match?(/\A\/?agents\z/i)
        return {'kind'=>'agents'}
      end
      if (m = q.match(/\A\/?(?:rails|console)\s+(.+)\z/m))
        return {'kind'=>'console','expression'=>m[1]}
      end
      if q.match?(/\A[A-Z][A-Za-z0-9_:]*\./)
        return {'kind'=>'console','expression'=>q}
      end
      if q.match?(/\A\/?models\z/i)
        return {'kind'=>'models'}
      end
      if (m = q.match(/\A\/?schema\s+([A-Z][A-Za-z0-9_:]*)\z/))
        return {'kind'=>'schema','model'=>m[1]}
      end
      if (m = q.match(/\A\/?ubuntu\s+(search|show|plan|install|docs|integrate|setup|catalog)\s+([a-z0-9][a-z0-9+ ._-]{0,100})\z/i))
        return {'kind'=>'ubuntu','operation'=>m[1].downcase,'package'=>m[2].strip.downcase}
      end
      if q.match?(/\A\/?ubuntu(?:\s+(?:status|refresh|sources))?\z/i)
        return {'kind'=>'ubuntu','operation'=>q.downcase.end_with?('refresh') ? 'refresh' : q.downcase.end_with?('sources') ? 'sources' : 'status'}
      end
      if (m = q.match(/\A\/?app\s+(describe|activate)\s+([a-z0-9][a-z0-9+.-]+)\z/))
        return {'kind'=>'application','operation'=>m[1],'package'=>m[2]}
      end
      if (m = q.match(/\A\/?app\s+run\s+([a-z0-9][a-z0-9+.-]+)\s+([a-z][a-z0-9_.-]*)(?:\s+(\{.*\}))?\z/m))
        return {'kind'=>'application','operation'=>'run','package'=>m[1],'action'=>m[2],'inputs'=>m[3] ? JSON.parse(m[3]) : {}}
      end
      if (m=q.match(/\A\/?(?:execute\s+)?app\.(\d+)\.([a-z][a-z0-9_.-]*)(?:\s+(\{.*\}))?\z/m))
        return {'kind'=>'application','operation'=>'run','adapter_id'=>m[1].to_i,'action'=>m[2],'inputs'=>m[3] ? JSON.parse(m[3]) : {}}
      end
      if (m=q.match(/\A\/?(?:execute\s+)?ubuntu\.(status|search|show|plan|install|docs|refresh|integrate|setup|catalog|sources)(?:\s+(\{.*\}))?\z/m))
        payload=m[2] ? JSON.parse(m[2]) : {}
        raise ArgumentError,'Ubuntu actions accept a package field only' unless (payload.keys-%w[package]).empty?
        return {'kind'=>'ubuntu','operation'=>m[1],'package'=>payload['package']}
      end
      if q.match?(/\A\/?agents\.list\z/)
        return {'kind'=>'agents'}
      end
      if (m = q.match(/\A\/?(?:execute\s+)?([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)(?:\s+(\{.*\}))?\z/m))
        return {'kind'=>'capability','intent'=>m[1],'payload'=>m[2] ? JSON.parse(m[2]) : {}}
      end
      if q.match?(/\A(?:please )?(?:list|show)(?: me)?(?: all)? my susus?[.!]?\z/i)
        return {'kind'=>'capability','intent'=>'susu.list','payload'=>{}}
      end
      return {'kind'=>'help'} if q.match?(/\A\/?(?:help|hello|hi|hey)(?: nevaeh)?[!.]?\z/i)
      if (m = q.match(/\A\/?(?:pause|activate) workers? (\d+)\z/i))
        return {'kind'=>'worker_status','id'=>m[1].to_i,'status'=>q.match?(/\A\/?pause/i) ? 'paused' : 'active'}
      end
      if (m = q.match(/\A(?:please )?create (?:a )?studio project (?:called |named )?["“]?(.+?)["”]?\z/i))
        return {'kind'=>'project','name'=>m[1].strip}
      end
      if (m = q.match(/\A(?:please )?(?:create|open) (?:a )?ticket (?:for |about )(.+)\z/im))
        return {'kind'=>'ticket','text'=>m[1].strip}
      end
      if (m = q.match(/\A\/?(create|read|list|show|update|delete|remove)\s+([a-z_]+)(?:\s+(\d+))?(?:\s+(\{.*\}))?\z/im))
        op = {'list'=>'read','show'=>'read','delete'=>'destroy','remove'=>'destroy'}.fetch(m[1].downcase,m[1].downcase)
        key = ALIASES.fetch(m[2].downcase,m[2].downcase)
        Resources.definition(key)
        attrs = m[4] ? JSON.parse(m[4]) : {}
        raise ArgumentError, 'Update/delete requires a record ID' if %w[update destroy].include?(op) && !m[3]
        raise ArgumentError, 'Create cannot include a record ID' if op == 'create' && m[3]
        return {'kind'=>'resource','operation'=>op,'resource'=>key,'id'=>m[3]&.to_i,'attributes'=>attrs}
      end
      if (m = q.match(/\A\/execute\s+([a-z][a-z0-9_.]+)\s+(\{.*\})\z/im))
        return {'kind'=>'capability','intent'=>m[1],'payload'=>JSON.parse(m[2])}
      end
      if (m = q.match(/\A\/train\s+(\d+)\s+(\{.*\})\z/im))
        return {'kind'=>'train','id'=>m[1].to_i,'options'=>JSON.parse(m[2])}
      end
      if (m = q.match(/\A\/checkpoint\s+(\d+)\z/i))
        return {'kind'=>'checkpoint','id'=>m[1].to_i}
      end
      if (m = q.match(/\A\/model\s+(\d+)\s+(.+)\z/im))
        return {'kind'=>'model','id'=>m[1].to_i,'prompt'=>m[2]}
      end
      if (m = q.match(/\A\/write\s+(caption|post|description|script)\s+(\{.*\})\z/im))
        return {'kind'=>'write','format'=>m[1],'context'=>JSON.parse(m[2])}
      end
      if (m = q.match(/\A\/?(resources|capabilities|status|briefing)\z/i))
        return {'kind'=>m[1].downcase}
      end
      if (m = q.match(/\A\/?(run|review|forget|build|activate|approve)\s+(\d+)\z/i))
        return {'kind'=>m[1].downcase,'id'=>m[2].to_i}
      end
      if (m = q.match(/\A\/learn\s+(\S+)\z/i))
        return {'kind'=>'learn','url'=>m[1]}
      end
      if (m = q.match(/\A\/remember\s+([^:]+):\s*(.+)\z/im))
        raise ArgumentError, 'Choose a memory category from your memory contract' unless NevaehOsConsent::CATEGORIES.include?(m[1])
        return {'kind'=>'remember','category'=>m[1],'text'=>m[2]}
      end
      return {'kind'=>'search','query'=>q.sub(/\A\/search\s+/i,'')} if q.match?(/\A\/search\s+/i)
      raise ArgumentError, 'Unknown command. Use /help for the command vocabulary.' if q.start_with?('/')
      {'kind'=>'search','query'=>q}
    rescue JSON::ParserError
      raise ArgumentError, 'Fields must be a valid JSON object. Use /resources to see accepted fields.'
    end
  end
end
