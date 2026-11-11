# frozen_string_literal: true
require 'digest'
module NevaehOs
  module WatchContract
    FIELDS={
      'ubuntu_package'=>%w[package refresh], 'ubuntu_catalog'=>%w[query refresh], 'ubuntu_sources'=>[],
      'github_repository'=>%w[repository branch credential_slug], 'github_account'=>%w[owner account_type credential_slug]
    }.freeze
    PLACEHOLDERS=%w[@event.package @event.repository @event.branch @event.version @event.entity @event.source].freeze
    module_function
    def validate!(kind:,target:,response:,template:)
      fields=FIELDS.fetch(kind) { raise ArgumentError,'Unsupported watcher kind' }
      raise ArgumentError,'Watcher target must match its documented fields' unless target.is_a?(Hash) && (target.keys-fields).empty? && target.to_json.bytesize<=4000
      case kind
      when 'ubuntu_package'
        raise ArgumentError,'Use one Ubuntu package name' unless target['package'].to_s.match?(/\A[a-z0-9][a-z0-9+.-]{1,100}\z/)
      when 'ubuntu_catalog'
        raise ArgumentError,'Use a specific catalog query (1–100 characters)' unless target['query'].is_a?(String) && target['query'].match?(/\A[a-zA-Z0-9+._ -]{1,100}\z/)
      when 'github_repository'
        raise ArgumentError,'Use owner/repository' unless target['repository'].to_s.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,38}/[a-zA-Z0-9_.-]{1,100}\z}) && !target['repository'].include?('..')
        raise ArgumentError,'Use a named branch without traversal' unless target['branch'].to_s.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_./-]{0,100}\z}) && !target['branch'].include?('..')
      when 'github_account'
        raise ArgumentError,'Use a GitHub user or organization name' unless target['owner'].to_s.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,38}\z/)
        raise ArgumentError,'account_type must be user or organization' unless %w[user organization].include?(target['account_type'])
      end
      if target.key?('refresh')
        raise ArgumentError,'refresh must be true or false' unless [true,false].include?(target['refresh'])
      end
      if target['credential_slug']
        raise ArgumentError,'Use a Vault credential slug, never a token' unless target['credential_slug'].is_a?(String) && target['credential_slug'].match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,120}\z/)
      end
      raise ArgumentError,'Automatic update is supported for a selected Ubuntu package only' if response=='update' && kind!='ubuntu_package'
      raise ArgumentError,'Use a bounded structured command template' unless template.is_a?(Hash) && template.to_json.bytesize<=16000
      if response=='command'
        raise ArgumentError,'A command template needs an executable kind' unless %w[resource capability console ubuntu application run worker_status project ticket write model learn review build activate approve train checkpoint].include?(template['kind'])
        expand(template,PLACEHOLDERS.to_h { |key| [key,'example'] })
      elsif template.present?
        raise ArgumentError,'command_template is used only with response=command'
      end
      true
    end
    def expand(value,event,depth=0)
      raise ArgumentError,'Watcher command template is nested too deeply' if depth>12
      case value
      when Hash then value.to_h { |key,item| [key,expand(item,event,depth+1)] }
      when Array then value.map { |item| expand(item,event,depth+1) }
      when String
        return value unless value.start_with?('@event.')
        raise ArgumentError,'Use a supported whole-value @event placeholder' unless PLACEHOLDERS.include?(value) && event.key?(value)
        event.fetch(value)
      else value
      end
    end
    def fingerprint(watcher)
      Digest::SHA256.hexdigest(JSON.generate([watcher.kind,watcher.target,watcher.condition,watcher.response,watcher.command_template,watcher.nevaeh_os_agent_id]))
    end
  end
end
