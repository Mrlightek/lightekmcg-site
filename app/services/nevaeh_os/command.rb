# frozen_string_literal: true
require 'json'
module NevaehOs
  module Command
    HELP = <<~TEXT.freeze
      I'm Nevaeh. Tell me what you need, or use a command:
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
