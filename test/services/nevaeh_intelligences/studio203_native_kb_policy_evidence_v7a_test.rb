# frozen_string_literal: true
require 'test_helper'
require 'digest'
require 'json'
require 'time'

class Studio203NativeKbPolicyEvidenceV7aTest < ActiveSupport::TestCase
  E = NevaehIntelligences::Studio203NativeKbPolicyEvidenceV7a
  Ticket = Struct.new(:id, :extra_fields) { def persisted? = true }
  Article = Struct.new(:id, :metadata, :article_type) { def persisted? = true }
  ACCEPT = {'schema_version'=>1, 'requirements'=>[{'rule'=>'require_published','value'=>true}, {'rule'=>'include_disabled','value'=>false}]}
  SHA = Digest::SHA256.hexdigest(JSON.generate(ACCEPT))
  POLICY_SHA = 'a' * 64
  EXPIRES = '2099-01-01T00:00:00Z'
  class Resolver
    class << self; attr_accessor :articles; end
    def self.for(capability:)
      raise 'unexpected capability' unless capability == E::CAPABILITY
      articles || []
    end
  end
  def ticket
    Ticket.new(211, {'project_tracking'=>{'key'=>'STUDIO-203'}})
  end
  def meta
    {'nevaeh_capability'=>E::CAPABILITY, 'policy_status'=>'approved',
     'policy_scope'=>'review_only', 'policy_tracking_key'=>'STUDIO-203',
     'acceptance_sha256'=>SHA, 'policy_version'=>'1',
     'policy_approval_id'=>'local-test-anchor', 'policy_digest'=>POLICY_SHA,
     'policy_valid_until'=>EXPIRES, 'policy_revoked'=>false}
  end
  def registry
    {'local-test-anchor'=>{'article_id'=>42,'version'=>'1','status'=>'approved',
                           'capability'=>E::CAPABILITY,'policy_digest'=>POLICY_SHA}}
  end
  def setup
    Resolver.articles = [Article.new(42, meta, 'guide')]
  end
  def verify(anchor: registry)
    E.verify(ticket: ticket, structured: ACCEPT, acceptance_sha256: SHA,
             resolver: Resolver, approval_registry: anchor)
  end
  def test_independently_anchored_review_only_policy
    result = verify
    assert_equal true, result['verified']
    assert_equal false, result['execution_authorized']
    assert_equal true, result['human_review_required']
    assert_equal SHA, result['acceptance_sha256']
  end
  def test_no_external_approval_registry_denied
    assert_raises(E::ReviewRequired) { verify(anchor: nil) }
    assert_raises(E::ReviewRequired) { verify(anchor: {}) }
  end
  def test_missing_article_denied
    Resolver.articles = []
    assert_raises(E::ReviewRequired) { verify }
  end
  def test_revocation_or_expiry_denied
    Resolver.articles = [Article.new(42, meta.merge('policy_revoked'=>true), 'guide')]
    assert_raises(E::ReviewRequired) { verify }
    Resolver.articles = [Article.new(42, meta.merge('policy_valid_until'=>'2020-01-01T00:00:00Z'), 'guide')]
    assert_raises(E::ReviewRequired) { verify }
  end
  def test_approval_integrity_mismatch_denied
    bad = registry.deep_dup
    bad['local-test-anchor']['policy_digest'] = 'b' * 64
    assert_raises(E::ReviewRequired) { verify(anchor: bad) }
  end
  def test_conflicting_policy_denied
    Resolver.articles = [Article.new(42, meta, 'guide'), Article.new(42, meta, 'reference')]
    assert_raises(E::ReviewRequired) { verify }
  end
  def test_unapproved_troubleshooting_article_denied
    Resolver.articles = [Article.new(42, meta.merge('policy_status'=>'draft'), 'troubleshooting')]
    assert_raises(E::ReviewRequired) { verify }
  end
  def test_ticket_and_acceptance_mismatch_denied
    assert_raises(E::ReviewRequired) do
      E.verify(ticket: Ticket.new(3, {'project_tracking'=>{'key'=>'OTHER'}}), structured: ACCEPT,
               acceptance_sha256: SHA, resolver: Resolver, approval_registry: registry)
    end
    assert_raises(E::ReviewRequired) do
      E.verify(ticket: ticket, structured: ACCEPT, acceptance_sha256: 'f' * 64,
               resolver: Resolver, approval_registry: registry)
    end
  end
end
