# frozen_string_literal: true
module NevaehOs
  module Agents
    DEFAULTS={'nevaeh'=>['Nevaeh','Core operator'],'sage'=>['Sage','Planning and analysis'],'muse'=>['Muse','Creative production'],'warden'=>['Warden','Operations and verification']}.freeze
    module_function
    def resolve!(reference,actor)
      if DEFAULTS.key?(reference.to_s.downcase)
        key=reference.downcase
        existing=NevaehOsAgent.find_by(user:actor,system_key:key)
        raise ArgumentError,'This specialist was deleted; create a replacement role explicitly' if existing&.deleted_at

        NevaehOsAgent.find_or_create_by!(user:actor,system_key:key) { |agent| agent.name,agent.role=DEFAULTS.fetch(key) }
      else
        scope=NevaehOsAgent.where(user:actor,deleted_at:nil)
        id=reference.to_s.delete_prefix('custom-')
        id.match?(/\A\d+\z/) ? scope.find(id) : (scope.find_by(system_key:reference.to_s.downcase) || scope.where('LOWER(name) = ?',reference.to_s.downcase).first!)
      end
    end
    def capability(command)
      case command['kind']
      when 'production' then 'studio.direct.production'
      when 'campaign_produce' then 'marketing.campaign.produce'
      when 'improve' then 'nevaeh.improve'
      when 'goal','goal_control' then 'nevaeh.goal'
      when 'growth_plan' then 'growth.plan'
      when 'growth_review' then 'growth.review'
      when 'capability' then command['intent']
      when 'watch' then "watcher.#{command['operation']}"
      when 'ubuntu' then "ubuntu.#{command['operation']}"
      when 'application' then "application.#{command['operation']}"
      when 'console' then 'rails.console'
      when 'resource' then "resource.#{command['resource']}.#{command['operation']}"
      else "nevaeh.#{command['kind']}"
      end
    end
    def authorize!(command,actor)
      return unless command['agent_id']
      agent=NevaehOsAgent.where(user:actor).find(command['agent_id'])
      raise ArgumentError,'This agent is paused' unless agent.enabled? && agent.deleted_at.nil?
      allowed=agent.allowed_capabilities
      key=capability(command)
      unless allowed.empty? || allowed.any? { |entry| entry==key || (entry.end_with?('.*') && key.start_with?(entry.delete_suffix('*'))) }
        raise ArgumentError,"#{agent.name} is not assigned capability #{key}"
      end
      agent
    end
  end
end
