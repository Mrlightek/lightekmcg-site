# frozen_string_literal: true
require 'test_helper'
require 'tmpdir'
require 'securerandom'
require 'json'

class Studio203PolicyApprovalJournalV7aTest < ActiveSupport::TestCase
  J = NevaehIntelligences::Studio203PolicyApprovalJournalV7a
  def setup
    @dir = Dir.mktmpdir('studio203-approval-journal-')
    @file = File.join(@dir, 'approvals.jsonl')
    @key = SecureRandom.random_bytes(48)
    @events = []
  end
  def teardown
    File.delete(@file) if File.file?(@file)
    File.delete(File.join(@dir, 'link')) if File.symlink?(File.join(@dir, 'link'))
    Dir.rmdir(@dir) if Dir.exist?(@dir)
  end
  def append(action: 'approved', id: 'test-approval-001', article: 42, digest: 'a' * 64, version: 1)
    event = {
      'sequence' => @events.length + 1,
      'action' => action,
      'approval_id' => id,
      'article_id' => article,
      'version' => version,
      'capability' => 'studio.capabilities.discovery',
      'policy_digest' => digest,
      'approver' => 'test-authority',
      'approved_at' => '2026-10-20T00:00:00Z',
      'valid_until' => '2099-01-01T00:00:00Z',
      'prior_mac' => @events.last&.fetch('mac') || '0' * 64
    }
    event['mac'] = J.mac_for(event, @key)
    @events << event
    write
  end
  def write
    File.open(@file, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| @events.each { |row| f.puts JSON.generate(row) } }
    File.chmod(0o600, @file)
  end
  def read(key: @key, path: @file, now: Time.utc(2026,10,21))
    J.load_registry(path: path, hmac_key: key, now: now)
  end
  def test_signed_approval_yields_review_only_registry
    append
    registry = read
    assert_equal 'approved', registry.fetch('test-approval-001').fetch('status')
    assert_equal 42, registry.fetch('test-approval-001').fetch('article_id')
    refute registry.fetch('test-approval-001').key?('execution_authorized')
  end
  def test_signed_revocation_removes_policy_eligibility
    append
    append(action: 'revoked')
    assert_equal 'revoked', read.fetch('test-approval-001').fetch('status')
  end
  def test_missing_key_or_missing_journal_is_rejected
    append
    assert_raises(J::ReviewRequired) { read(key: nil) }
    assert_raises(J::ReviewRequired) { read(path: File.join(@dir, 'missing')) }
  end
  def test_wrong_key_and_modified_bytes_rejected
    append
    assert_raises(J::ReviewRequired) { read(key: SecureRandom.random_bytes(48)) }
    File.write(@file, File.read(@file).sub('test-authority', 'fake-authority'))
    assert_raises(J::ReviewRequired) { read }
  end
  def test_missing_or_reordered_event_rejected
    append
    append(action: 'revoked')
    @events.shift
    write
    assert_raises(J::ReviewRequired) { read }
  end
  def test_expired_record_never_becomes_approved
    append
    assert_equal 'expired', read(now: Time.utc(2100, 1, 1)).fetch('test-approval-001').fetch('status')
  end
  def test_reuse_and_unanchored_revocation_rejected
    append
    append
    assert_raises(J::ReviewRequired) { read }
    @events.clear
    append(action: 'revoked')
    assert_raises(J::ReviewRequired) { read }
  end
  def test_symlinks_and_weak_file_permissions_rejected
    append
    File.symlink(@file, File.join(@dir, 'link'))
    assert_raises(J::ReviewRequired) { read(path: File.join(@dir, 'link')) }
    File.chmod(0o666, @file)
    assert_raises(J::ReviewRequired) { read }
  end
end
