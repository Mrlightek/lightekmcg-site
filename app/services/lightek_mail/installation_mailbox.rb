# frozen_string_literal: true

module LightekMail
  class InstallationMailbox
    def initialize(peer)
      @peer = peer
      raise LightekPeople::Access::Denied unless peer.active? && LightekPeople::LifecycleAccess.active?(peer.merchant)
    end

    def provision!
      @peer.with_lock do
        existing = Account.find_by(installation_peer: @peer)
        if existing
          raise ArgumentError, 'This installation mailbox has been retired.' if existing.deleted_at?

          return existing
        end

        domain = LightekEmailProvisioningService.verified_domain!
        label = @peer.site.host.split('.').first.parameterize.first(17).presence || "site"
        address = "installation-#{label}-#{@peer.key.delete('-')}@#{domain.name}"
        Account.create!(user: @peer.merchant, domain: domain, installation_peer: @peer, address: address,
          display_name: @peer.site.host.first(120), enabled: true, storage_limit: 250.megabytes,
          minute_limit: 2, hour_limit: 10, daily_limit: 20)
      end
    end

    def inbox(folder)
      mailbox = provision!
      raise ArgumentError, 'Choose inbox, sent, or outbox.' unless %w[inbox sent outbox].include?(folder)

      messages = MessageFolder.scope(mailbox, folder).order(id: :desc).limit(40)
      {address: mailbox.address, sending_ready: mailbox.sending_ready?, messages: messages.map { |message| summary(message) }}
    end

    def read(id)
      message = account.messages.visible.find(id)
      message.update!(read_at: Time.current) if message.direction == 'inbound' && !message.read_at?
      summary(message).merge(text: message.text_body.to_s.first(40_000), address: message.account.address)
    end

    def send!(attributes)
      text = attributes.fetch('text').to_s
      key = attributes.fetch('request_key').to_s
      raise ArgumentError, 'Write a message of 1–8,000 characters.' unless text.strip.length.between?(1, 8_000)
      raise ArgumentError, 'Invalid mail request.' unless LightekTeam::Network::REQUEST_KEY.match?(key)

      mailbox = account
      message = Submission.create!(account: mailbox, attributes: attributes.except('request_key'), idempotency_key: "installation-#{key}")
      summary(message)
    end

    private

    def account
      Account.mailboxes.find_by!(installation_peer: @peer)
    end

    def summary(message)
      {id: message.id, from: message.from_address, to: message.to_addresses.first(20), subject: message.subject,
        status: message.state, unread: message.direction == 'inbound' && !message.read_at?, created_at: message.created_at.iso8601}
    end
  end
end
