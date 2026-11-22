# frozen_string_literal: true

module LightekTeam
  class Network
    SUBJECT = /\Auser-[1-9]\d{0,18}\z/
    REQUEST_KEY = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/

    def initialize(peer:, subject:, actor_name:)
      @peer = peer
      @subject = subject.to_s
      @actor_name = owner? ? peer.merchant.full_name : actor_name.to_s.strip.first(120)
      raise LightekPeople::Access::Denied unless peer.active? && LightekPeople::LifecycleAccess.active?(peer.merchant)
      raise ArgumentError, 'Invalid installation identity.' unless (owner? || SUBJECT.match?(@subject)) && @actor_name.present?
    end

    def list
      allowed = channels.includes(host_peer: :site, partner_peer: :site).order(updated_at: :desc).limit(100)
      {channels: allowed.map { |channel| summary(channel) }}
    end

    def create!(name:, address:)
      require_owner!
      address = address.to_s.strip.downcase
      peers = LightekReservations::Peer.enabled_installations.where.not(id: @peer.id)
      candidates = if address.include?('@')
        mailboxes = LightekMail::Account.mailboxes.where(address: address).where.not(installation_peer_id: nil)
        peers.where(id: mailboxes.select(:installation_peer_id))
      else
        peers.joins(:site).where(dymond_site_sites: {host: address})
      end
      matches = candidates.includes(:order, :merchant).select { |candidate| available?(candidate) }
      unless matches.one?
        raise ArgumentError, 'Enter the hostname or branded mailbox of another connected installation.'
      end

      channel = NetworkChannel.create!(host_peer: @peer, partner_peer: matches.first, key: SecureRandom.hex(16), name: name)
      summary(channel)
    end

    def show(key, before: nil)
      channel = channels.find_by!(key: key)
      require_connected!(channel) if channel.partner_peer_id == @peer.id && channel.accepted_at?
      scope = channel.messages
      scope = scope.where('id < ?', before.to_i) if before.present?
      rows = scope.order(id: :desc).includes(peer: :site).limit(41).to_a
      older_than = rows[39].id if rows.size > 40
      summary(channel).merge(messages: rows.first(40).reverse.map { |message|
        {author: message.author, organization: message.peer.site.host, body: message.body, created_at: message.created_at.iso8601}
      }, older_than: older_than,
        members: owner? ? channel.members.where(peer: @peer).pluck(:subject) : [],
        participants: channel.accepted_at? && !channel.closed_at? ? participants(channel) : [])
    end

    def accept!(key)
      require_owner!
      change!(key) do |channel|
        raise LightekPeople::Access::Denied unless channel.partner_peer_id == @peer.id && !channel.closed_at?

        raise ArgumentError, 'The host installation is unavailable.' unless available?(channel.host_peer)

        channel.update!(accepted_at: Time.current) unless channel.accepted_at?
      end
    end

    def disconnect!(key)
      require_owner!
      change!(key) { |channel| channel.update!(closed_at: Time.current) unless channel.closed_at? }
    end

    def member!(key, subject:, display_name:, remove:)
      require_owner!
      raise ArgumentError, 'Choose an active teammate.' unless SUBJECT.match?(subject.to_s)

      change!(key) do |channel|
        require_connected!(channel)
        scope = channel.members.where(peer: @peer, subject: subject)
        if remove
          scope.delete_all
        else
          name = display_name.to_s.strip.first(120)
          raise ArgumentError, 'Choose a teammate with a display name.' if name.blank?

          (scope.first || scope.new).update!(display_name: name)
        end
      end
    end

    def post!(key, body:, request_key:)
      raise ArgumentError, 'Invalid message request.' unless REQUEST_KEY.match?(request_key.to_s)

      change!(key) do |channel|
        require_connected!(channel)
        body = body.to_s.strip
        messages = channel.messages.where(peer: @peer, subject: @subject, request_key: request_key)
        saved = messages.first
        raise ArgumentError, 'This request belongs to a different message.' if saved && saved.body != body

        messages.create!(body: body, author: @actor_name) unless saved
      end
    end

    def office!(channel_key, operation, values)
      channel = channels.find_by!(key: channel_key)
      channel.with_lock do
        channels.find(channel.id)
        host_history = channel.host_peer_id == @peer.id && channel.closed_at? && channel.accepted_at?
        require_connected!(channel) unless operation.in?(%w[list show]) && host_history
        files = LightekOffice::NetworkFile.where(channel: channel)
        if operation == 'list'
          return {files: files.order(updated_at: :desc).limit(100).map { |file| office_summary(file) }}
        end

        key = values.fetch('file_key').to_s
        raise ArgumentError, 'Invalid file key.' unless key.match?(/\A[0-9a-f]{32}\z/)
        file = operation == 'create' ? files.find_or_initialize_by(key: key) : files.find_by!(key: key)
        return office_summary(file).merge(content: file.content) if operation == 'show'

        kind = file.new_record? ? values['kind'] : file.kind
        rich_text = kind == 'document' && ActiveModel::Type::Boolean.new.cast(values['rich_text']) == true
        raw = values.fetch('content').to_s
        if rich_text
          content = LightekOffice::Document.prepare!(raw)
        else
          LightekOffice::Content.validate!(kind, raw)
          content = raw
        end

        if operation == 'create' && file.persisted?
          unless file.editor_peer_id == @peer.id && file.kind == values['kind'] && file.title == values['title'] &&
              file.content == content && file.rich_text? == rich_text
            raise ArgumentError, 'This file request already exists.'
          end
          return office_summary(file)
        end

        if operation == 'update' && file.lock_version.to_s != values['lock_version'].to_s
          raise ArgumentError, 'The file changed. Reload it before saving again.'
        end

        file.update!(kind: kind, title: values['title'], content: content, rich_text: rich_text, editor_peer: @peer, editor_name: @actor_name)
        office_summary(file)
      end
    end

    private

    def office_summary(file)
      {key: file.key, title: file.title, kind: file.kind, rich_text: file.rich_text?, lock_version: file.lock_version,
        editor: file.editor_name, organization: file.editor_peer.site.host}
    end

    def owner? = @subject == 'owner'

    def require_owner!
      raise LightekPeople::Access::Denied unless owner?
    end

    def available?(peer)
      peer.active? && LightekPeople::LifecycleAccess.active?(peer.merchant)
    end

    def channels
      host = NetworkChannel.where(host_peer: @peer)
      partner = NetworkChannel.where(partner_peer: @peer, closed_at: nil)
      return host.or(partner) if owner?

      memberships = NetworkMember.where(peer: @peer, subject: @subject).select(:channel_id)
      host.or(partner).where(id: memberships, closed_at: nil).where.not(accepted_at: nil)
    end

    def participants(channel)
      owners = [channel.host_peer, channel.partner_peer].map do |peer|
        {name: peer.merchant.full_name, organization: peer.site.host}
      end
      peers = {channel.host_peer_id => channel.host_peer.site.host, channel.partner_peer_id => channel.partner_peer.site.host}
      owners + channel.members.order(:display_name).limit(200).map do |member|
        {name: member.display_name, organization: peers.fetch(member.peer_id)}
      end
    end

    def require_connected!(channel)
      unless channel.accepted_at? && !channel.closed_at? && available?(channel.other_peer(@peer))
        raise ArgumentError, 'This installation connection is unavailable.'
      end
    end

    def change!(key)
      channel = channels.find_by!(key: key)
      channel.with_lock do
        channels.find(channel.id)
        yield channel
        summary(channel)
      end
    end

    def summary(channel)
      peer = channel.other_peer(@peer)
      status = if channel.closed_at?
        'disconnected'
      elsif channel.accepted_at?
        'connected'
      elsif channel.partner_peer_id == @peer.id
        'invited'
      else
        'pending'
      end
      {key: channel.key, name: channel.name, partner_host: peer.site.host, status: status}
    end
  end
end
