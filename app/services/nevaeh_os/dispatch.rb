# frozen_string_literal: true
module NevaehOs
  module Dispatch
    CAPABILITY = 'nevaeh.os.execute'
    module_function
    def register!
      capability = NevaehCapability.find_or_initialize_by(slug: CAPABILITY)
      if capability.new_record?
        capability.assign_attributes(name: 'Nevaeh Operating System', domain: 'nevaeh', intent_name: 'nevaeh_os_execute', handler: 'NevaehOs::Worker', queue: 'default', priority: 5,
          subject_type: 'NevaehOsAction', gatekeeper_capability: CAPABILITY, event_types: ['nevaeh.os.execute.requested'], enabled: true)
        capability.save!
      end
      unless capability.handler == 'NevaehOs::Worker' && capability.subject_type == 'NevaehOsAction' && capability.gatekeeper_capability == CAPABILITY
        raise ArgumentError, 'Operating capability binding does not match the installed worker'
      end
      capability
    end
    def submit!(actor:, command:, request_key:)
      raise ArgumentError, 'Request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      action = NevaehOsAction.find_or_create_by!(user: actor, request_key: request_key) { |row| row.command = command }
      action.with_lock do
        raise ArgumentError, 'Request key already belongs to different inputs' unless action.command == command
        Executor.authorize!(action) if action.status == 'pending'
        register!
        item = DymondDispatch::WorkItem.find_by(subject_type: 'NevaehOsAction', subject_id: action.id, kind: CAPABILITY)
        if action.status == 'pending' && !item
          Nevaeh.handle(event_type: 'nevaeh.os.execute.requested', source: 'nevaeh_os', subject: action, actor: actor,
            capability_hint: CAPABILITY, args: ['execute', {'action_id'=>action.id}], correlation_id: "nevaeh-os-#{action.id}")
        end
      end
      action
    rescue ArgumentError, ActiveRecord::RecordNotFound, Gatekeeper::AuthorizationDenied, LightekPwa::Policy::Denied => error
      if action&.persisted? && action.command==command
        action.with_lock do
          item=DymondDispatch::WorkItem.find_by(subject_type:'NevaehOsAction',subject_id:action.id,kind:CAPABILITY)
          action.update!(status:'failed',error:error.message[0,1000]) if action.status=='pending' && !item
        end
      end
      raise
    end
  end
end
