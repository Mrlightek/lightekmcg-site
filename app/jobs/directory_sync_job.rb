class DirectorySyncJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(employer_id)
    realm = LightekIdentity::Realm.find_by(employer_id: employer_id)
    return unless realm
    LightekIdentity::DirectoryPolicy.calendar!(realm)
    if realm.enabled? && realm.auto_join?
      GatekeeperNode.where(owner_type: 'User', owner_id: employer_id, status: 'healthy').each do |node|
        LightekIdentity::NodeBinding.find_or_create_by!(gatekeeper_node: node, realm: realm) unless node.local?
      end
    end
    realm.node_bindings.find_each { |binding| DirectoryNodeSyncJob.perform_later(binding.id) }
    # Exactly one future calendar-boundary reservation per employer. Membership
    # mutations enqueue immediate reconciliation without multiplying timers.
    dates = LightekPeople::Employment.where(employer_id: employer_id).pluck(:starts_on,:ends_on).flat_map { |first,last| [first,last&.next_day] }.compact.select { |date| date > Date.current }
    boundary = dates.min&.in_time_zone&.beginning_of_day
    next_time = [boundary,5.minutes.from_now].compact.min
    realm.with_lock do
      if realm.next_sync_at.nil? || realm.next_sync_at <= Time.current || realm.next_sync_at > next_time
        realm.update!(next_sync_at: next_time)
        self.class.set(wait_until: next_time).perform_later(employer_id)
      end
    end
  end
end
