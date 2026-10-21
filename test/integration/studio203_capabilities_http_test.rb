# STUDIO203_T6_HTTP_VERIFICATION_V3
# frozen_string_literal: true
require 'test_helper'
require 'json'
require 'securerandom'

class Studio203CapabilitiesHttpTest < ActionDispatch::IntegrationTest
  PATH = '/api/studio/capabilities'
  FORBIDDEN_KEYS = /\A(?:handler|queue|api_token|password_digest|secret|credential|private_key|access_token|refresh_token|execution_command|shell_command)\z/i
  FORBIDDEN_VALUES = /(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(?:ql)?:\/\/|redis:\/\/|Bearer\s+[\w.\-]+)/i

  setup do
    Current.reset if Current.respond_to?(:reset)
  end

  teardown do
    Current.reset if Current.respond_to?(:reset)
  end

  test 'unauthenticated HTTP GET is rejected' do
    get PATH, headers: json_headers
    assert_includes [302, 401, 403], response.status
    refute_equal 200, response.status
  end

  test 'authorized admin has HTTP 200 JSON with stable redacted content' do
    sign_in_as_role('super_admin')
    get PATH, headers: json_headers
    assert_response :success
    first = JSON.parse(response.body)
    assert first.is_a?(Hash) || first.is_a?(Array)
    verify_redaction(first)
    get PATH, headers: json_headers
    assert_response :success
    assert_equal first, JSON.parse(response.body), 'identical requests should be deterministic'
  end

  test 'authenticated client is forbidden by CanCanCan' do
    sign_in_as_role('client')
    get PATH, headers: json_headers
    assert_response :forbidden
  end

  test 'discovery is not Blender execution' do
    sign_in_as_role('super_admin')
    # A new Blender::Runner would indicate a dangerous dispatch boundary regression.
    if defined?(Blender::Runner)
      # Core Ruby only: protect the constructor, then restore it even if GET raises.
      runner_singleton = Blender::Runner.singleton_class
      owned_new = runner_singleton.instance_methods(false).include?(:new)
      original_new = runner_singleton.instance_method(:new) if owned_new
      runner_singleton.send(:define_method, :new) do |*_args, **_kwargs|
        raise 'STUDIO203_T6_VIOLATION: capability discovery attempted Blender::Runner.new'
      end
      begin
        get PATH, headers: json_headers
      ensure
        if owned_new
          runner_singleton.send(:define_method, :new, original_new)
        else
          runner_singleton.send(:remove_method, :new)
        end
      end
    else
      get PATH, headers: json_headers
    end
    assert_response :success
  end

  test 'disabled and unpublished metadata must not confer execution approval' do
    sign_in_as_role('super_admin')
    get PATH, headers: json_headers
    assert_response :success
    parsed = JSON.parse(response.body)
    recursively_check_execution_flags(parsed)
    # This endpoint is GET/read-only. It must not expose action URLs that trigger execution.
    refute_match(/(?:\/execute\b|\/dispatch\b|\/run\b)/i, response.body)
  end

  test 'invalid and duplicate capability records are rejected safely' do
    skip 'NevaehCapability missing' unless defined?(NevaehCapability)
    invalid = NevaehCapability.new
    assert_not invalid.valid?
    assert invalid.errors.any?
    slug = "studio203-t6-#{SecureRandom.hex(10)}"
    properties = {name: 'T6', slug: slug, domain: 'studio', intent_name: 'test', handler: 'noop', queue: 'default', priority: 1, enabled: false}
    properties.select! { |k, _| NevaehCapability.column_names.include?(k.to_s) }
    first = NevaehCapability.new(properties)
    if first.valid?
      first.save!
      duplicate = NevaehCapability.new(properties)
      assert_not duplicate.valid?, 'duplicate slug must not validate'
      assert duplicate.errors.attribute_names.include?(:slug)
    else
      skip "unable to form valid capability fixture: #{first.errors.attribute_names.join(', ')}"
    end
  ensure
    first.destroy! if defined?(first) && first&.persisted?
  end

  private

  def json_headers
    {'ACCEPT' => 'application/json'}
  end

  def sign_in_as_role(role)
    unique = SecureRandom.hex(12)
    user = User.create!(email_address: "studio203-t6-#{unique}@example.test", first_name: 'Studio', last_name: 'Verifier', password: 'Studio203-T6-Passphrase-Only!', password_confirmation: 'Studio203-T6-Passphrase-Only!', role: role)
    post '/session', params: {email_address: user.email_address, password: 'Studio203-T6-Passphrase-Only!'}
    assert_includes [302, 303], response.status, 'session login did not succeed; inspect local session controller'
    user
  end

  def verify_redaction(node)
    case node
    when Hash
      node.each do |key, value|
        refute_match FORBIDDEN_KEYS, key.to_s, "internal key exposed: #{key}"
        verify_redaction(value)
      end
    when Array
      node.each { |value| verify_redaction(value) }
    when String
      refute_match FORBIDDEN_VALUES, node, 'secret-like value leaked'
    end
  end

  def recursively_check_execution_flags(node)
    case node
    when Hash
      state = node.transform_keys(&:to_s)
      active = state['enabled'] == false || state['published'] == false
      if active
        %w[executable execution_approved gatekeeper_approved can_execute].each do |flag|
          assert_not_equal true, state[flag], "#{flag} must not be true on unavailable capability"
        end
      end
      state.each_value { |value| recursively_check_execution_flags(value) }
    when Array
      node.each { |value| recursively_check_execution_flags(value) }
    end
  end
end
