# frozen_string_literal: true
require 'json'
require 'openssl'
require 'digest'
require 'time'

module NevaehIntelligences
  # Read-only, independently controlled signed approvals. NOT execution authority.
  # This class contains no approve/revoke writer: the authorizing process is external.
  module Studio203PolicyApprovalJournalV7a
    class ReviewRequired < StandardError; end
    module_function
    MAX_BYTES = 1_048_576
    MAX_EVENTS = 1_000
    DIGEST = /\A[0-9a-f]{64}\z/
    REFERENCE = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{2,127}\z/
    ALLOWED = %w[approved revoked].freeze
    FIELDS = %w[sequence action approval_id article_id version capability policy_digest approver approved_at valid_until prior_mac mac].freeze
    # Fixed order is the serialization contract. External authority signs exactly this object.
    SIGNED_FIELDS = FIELDS - ['mac']
    def mac_for(data, key)
      OpenSSL::HMAC.hexdigest('SHA256', key, JSON.generate(SIGNED_FIELDS.to_h { |field| [field, data.fetch(field)] }))
    end
    def secure_equal?(a, b)
      return false unless a.is_a?(String) && b.is_a?(String) && a.bytesize == b.bytesize
      OpenSSL.fixed_length_secure_compare(a, b)
    end
    def load_registry(path:, hmac_key:, now: Time.now.utc)
      raise ReviewRequired, 'approval journal key unavailable' unless hmac_key.is_a?(String) && hmac_key.bytesize >= 32
      raise ReviewRequired, 'invalid journal path' unless path.is_a?(String) && !path.empty?
      stat = File.lstat(path)
      raise ReviewRequired, 'journal not regular or symlinked' unless stat.file? && !stat.symlink?
      raise ReviewRequired, 'journal permissions unsafe' unless (stat.mode & 0o022).zero?
      raise ReviewRequired, 'journal too large or empty' unless stat.size.between?(1, MAX_BYTES)
      # Read from the opened descriptor; reject replacement during reading.
      raw = File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise ReviewRequired, 'journal inode mismatch' unless before.ino == stat.ino && before.dev == stat.dev
        data = file.read(MAX_BYTES + 1)
        after = file.stat
        raise ReviewRequired, 'journal changed during read' unless before.size == after.size && before.mtime == after.mtime
        data
      end
      raise ReviewRequired, 'journal invalid length' if raw.bytesize > MAX_BYTES
      lines = raw.lines
      raise ReviewRequired, 'journal invalid event count' unless lines.length.between?(1, MAX_EVENTS) && raw.end_with?("\n")
      registry = {}
      last_mac = '0' * 64
      seen = {}
      lines.each_with_index do |line, index|
        event = JSON.parse(line)
        raise ReviewRequired, 'invalid journal event object' unless event.is_a?(Hash) && event.keys.sort == FIELDS.sort
        raise ReviewRequired, 'journal sequence invalid' unless event['sequence'] == index + 1
        raise ReviewRequired, 'journal chain broken' unless event['prior_mac'] == last_mac
        raise ReviewRequired, 'invalid signature' unless event['mac'].to_s.match?(DIGEST) && secure_equal?(event['mac'], mac_for(event, hmac_key))
        id = event['approval_id']
        raise ReviewRequired, 'invalid approval id' unless id.is_a?(String) && id.match?(REFERENCE)
        raise ReviewRequired, 'invalid action' unless ALLOWED.include?(event['action'])
        raise ReviewRequired, 'invalid digest' unless event['policy_digest'].to_s.match?(DIGEST)
        raise ReviewRequired, 'invalid approver' unless event['approver'].is_a?(String) && event['approver'].match?(REFERENCE)
        raise ReviewRequired, 'invalid article id' unless event['article_id'].is_a?(Integer) && event['article_id'] > 0
        raise ReviewRequired, 'invalid version' unless event['version'].is_a?(Integer) && event['version'] > 0
        raise ReviewRequired, 'invalid capability' unless event['capability'] == 'studio.capabilities.discovery'
        begin
          issued = Time.iso8601(event.fetch('approved_at'))
          expiry = Time.iso8601(event.fetch('valid_until'))
        rescue ArgumentError, TypeError
          raise ReviewRequired, 'invalid timestamps'
        end
        raise ReviewRequired, 'invalid approval lifetime' unless expiry > issued
        if event['action'] == 'approved'
          raise ReviewRequired, 'approval id reused' if seen[id]
          seen[id] = true
          registry[id] = {
            'article_id' => event['article_id'], 'version' => event['version'],
            'capability' => event['capability'], 'policy_digest' => event['policy_digest'],
            'status' => expiry > now ? 'approved' : 'expired',
            'approver' => event['approver'], 'approved_at' => event['approved_at'],
            'valid_until' => event['valid_until']
          }
        else
          existing = registry[id]
          raise ReviewRequired, 'revocation without approval' unless existing
          raise ReviewRequired, 'revocation metadata mismatch' unless existing.values_at('article_id', 'version', 'capability', 'policy_digest') == event.values_at('article_id', 'version', 'capability', 'policy_digest')
          existing['status'] = 'revoked'
        end
        last_mac = event['mac']
      end
      registry
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError => e
      raise ReviewRequired, "journal unavailable or malformed: #{e.class}"
    end
  end
end
