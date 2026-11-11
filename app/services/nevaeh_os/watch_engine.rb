# frozen_string_literal: true
require 'digest'
module NevaehOs
  module WatchEngine
    module_function
    def authorize!(watcher,active:true)
      actor=watcher.user.reload
      UbuntuPackages.authorize!(actor)
      raise ArgumentError,'Watcher is paused' if active && watcher.status!='active'
      Agents.authorize!({'kind'=>'watch','operation'=>'poll','agent_id'=>watcher.nevaeh_os_agent_id},actor)
      actor
    end
    def create!(actor:,attributes:)
      UbuntuPackages.authorize!(actor)
      raise ArgumentError,'Use a watcher definition object' unless attributes.is_a?(Hash) && attributes.to_json.bytesize<=24000
      allowed=%w[name kind target condition response command_template interval_minutes agent]
      raise ArgumentError,'Unknown watcher fields' if (attributes.keys-allowed).any?
      agent=Agents.resolve!(attributes.fetch('agent','warden'),actor)
      watcher=NevaehWatcher.new(attributes.except('agent').merge('user'=>actor,'nevaeh_os_agent'=>agent))
      watcher.save!
      agent.update!(autonomy:'scheduled') if agent.autonomy!='scheduled'
      watcher
    end
    def poll!(id,force:false)
      watcher=NevaehWatcher.find(id);token=SecureRandom.uuid;fingerprint=nil;claimed=false
      watcher.with_lock do
        authorize!(watcher)
        return 'busy' if watcher.lease_token.present? && watcher.lease_expires_at && watcher.lease_expires_at>Time.current
        return 'not_due' if !force && watcher.next_poll_at && watcher.next_poll_at>Time.current
        claimed=true
        fingerprint=WatchContract.fingerprint(watcher)
        watcher.update!(lease_token:token,lease_expires_at:35.minutes.from_now,next_poll_at:Time.current+watcher.interval_minutes.minutes)
      end
      snapshot=WatchSensors.snapshot(watcher)
      raise ArgumentError,'Watcher snapshot must contain at most 1000 bounded entities' unless snapshot.is_a?(Hash) && snapshot.size<=1000 && snapshot.to_json.bytesize<=500000 && snapshot.all? { |key,value| key.is_a?(String) && key.length.between?(1,240) && value.is_a?(Hash) }
      created=[]
      watcher.with_lock do
        return 'superseded' unless watcher.lease_token==token && WatchContract.fingerprint(watcher)==fingerprint
        authorize!(watcher)
        sequence=watcher.poll_sequence+1
        if watcher.initialized?
          snapshot.each do |entity,value|
            before=watcher.baseline[entity]
            change=before.nil? ? 'new' : before==value ? nil : 'updated'
            next unless change && (watcher.condition=='new_or_updated' || watcher.condition==change)
            identity=Digest::SHA256.hexdigest(JSON.generate([watcher.id,sequence,entity,before,value]))
            event=watcher.events.find_or_create_by!(event_key:identity) do |row|
              row.entity=entity;row.change=change;row.before_value=before || {};row.after_value=value
              row.plan={'definition_fingerprint'=>fingerprint,'response'=>watcher.response}
            end
            created << event.id
          end
        end
        watcher.update!(baseline:snapshot,initialized:true,poll_sequence:sequence,last_polled_at:Time.current,failures:0,error:nil,lease_token:nil,lease_expires_at:nil)
      end
      created.each { |event_id| WatchEventJob.perform_later(event_id) }
      'polled'
    rescue StandardError => error
      if watcher&.persisted?
        watcher.with_lock do
          if !claimed && watcher.status=='active' && watcher.lease_token.blank?
            watcher.update!(status:'paused',error:error.message[0,1000])
          elsif watcher.lease_token==token
            failures=watcher.failures+1
            watcher.update!(failures:failures,error:error.message[0,1000],status:failures>=3 ? 'paused' : watcher.status,lease_token:nil,lease_expires_at:nil)
          end
        end
      end
      raise
    end
    def tick!
      now=Time.current
      NevaehWatcher.where(status:'active').where('next_poll_at <= ?',now).where('lease_expires_at IS NULL OR lease_expires_at <= ?',now).order(:next_poll_at).limit(100).pluck(:id).each { |id| WatchPollJob.perform_later(id) }
      NevaehWatchEvent.where(status:'detected').order(:id).limit(100).pluck(:id).each { |id| WatchEventJob.perform_later(id) }
    end
    def receipt(watcher)
      {id:watcher.id,name:watcher.name,kind:watcher.kind,target:watcher.target.except('credential_slug'),condition:watcher.condition,response:watcher.response,status:watcher.status,
       initialized:watcher.initialized?,next_poll_at:watcher.next_poll_at,last_polled_at:watcher.last_polled_at,error:watcher.error,
       events:watcher.events.order(id: :desc).limit(20).map { |event| {id:event.id,identity:event.entity,entity:event.after_value['repository'] || event.after_value['package'] || event.after_value['source'] || event.entity,change:event.change,previous:event.before_value,current:event.after_value,status:event.execution_status,plan:event.plan,error:event.error,agent_run_id:event.nevaeh_agent_run_id} }}
    end
  end
end
