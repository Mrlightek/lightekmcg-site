# frozen_string_literal: true
class StudioSocialPublicationPollJob < ApplicationJob
  queue_as :studio
  def perform(id)
    publication=StudioPublication.find(id)
    claimed=false
    publication.with_lock do
      return unless publication.status=='publishing' && %w[tiktok instagram].include?(publication.platform)
      state=publication.metadata.fetch('social_submission',{})
      raise Studio::Publishers::SocialTransport::NeedsReview,'No remote publication reference was saved; reconcile the provider account' unless state['remote_id']
      count=state.fetch('poll_count',0).to_i
      limit=publication.platform=='instagram' ? 5 : 120
      raise Studio::Publishers::SocialTransport::NeedsReview,'Provider processing exceeded automatic polling; reconcile the saved reference' if count>=limit
      previous=state['poll_claimed_at'] && Time.iso8601(state['poll_claimed_at'])
      if previous && previous>5.minutes.ago
        self.class.set(wait:1.minute).perform_later(id)
        return
      end
      publication.update!(metadata:publication.metadata.merge('social_submission'=>state.merge('poll_count'=>count+1,'poll_claimed_at'=>Time.current.iso8601)))
      claimed=true
    end
    actor=User.find(publication.metadata.fetch('user_id'))
    Studio::Publishers::SocialTransport.connection!(publication.metadata.fetch('connection_id'),actor:actor,project:publication.studio_project)
    Studio::Gatekeeper::Client.authorize!(capability:"studio.publish.#{publication.platform}",subject:publication,context:{project_id:publication.studio_project_id,artifact_id:publication.artifact_id})
    if publication.metadata['director_assembly_id']
      assembly=publication.production.studio_operations.where(status:'completed',capability:'studio.direct.assemble').find(publication.metadata['director_assembly_id'])
      Studio::Director::Finishing.verify_sources!(assembly)
    end
    result=Studio::Publishers::Registry.fetch(publication.platform).new(publication).refresh!
    publication.with_lock do
      return if publication.status=='cancelled'
      state=publication.metadata.fetch('social_submission',{}).except('poll_claimed_at')
      attrs={metadata:publication.metadata.merge('social_submission'=>state),error_message:nil}
      attrs.merge!(status:'published',published_at:Time.current) if result['status']=='published'
      publication.update!(attrs)
    end
    self.class.set(wait:1.minute).perform_later(id) if publication.status=='publishing'
  rescue Studio::Publishers::SocialTransport::NeedsReview => error
    publication&.update!(status:'needs_review',error_message:error.message.to_s.first(1000)) unless publication&.status=='cancelled'
  rescue Net::OpenTimeout,Net::ReadTimeout,Net::WriteTimeout,SocketError,IOError => error
    if claimed
      release_claim(publication)
      self.class.set(wait:1.minute).perform_later(id) if publication.reload.status=='publishing'
    end
  rescue StandardError=>error
    publication&.update!(status:'failed',error_message:error.message.to_s.first(1000)) unless publication&.status=='cancelled'
    raise
  end
  private
  def release_claim(publication)
    publication.with_lock do
      publication.update!(metadata:publication.metadata.merge('social_submission'=>publication.metadata.fetch('social_submission',{}).except('poll_claimed_at')))
    end
  end
end
