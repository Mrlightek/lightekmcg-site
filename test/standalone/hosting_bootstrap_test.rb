# Actual Vault encryption, persisted build settings and signed GitHub identities;
# external GitHub/host services are replaced at their boundary.
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_support/all"
require "tmpdir"
require "pathname"
require "jwt"
require "fiddle"
require "base64"

BOOTSTRAP_ROOT = Pathname.new(File.expand_path("../..", __dir__))
module Rails
  class << self
    attr_accessor :root
    def cache = @cache ||= ActiveSupport::Cache::MemoryStore.new
  end
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :email_address; t.string :role }
  create_table(:gatekeeper_nodes) { |t| t.string :name }
  create_table(:provisioning_requests) { |t| t.string :name }
end
%w[20260927111553_create_lightek_vault 20261107140000_create_application_launches 20261107160000_add_image_build_identity].each do |name|
  source = BOOTSTRAP_ROOT.join("db/migrate/#{name}.rb").read
  eval(source.sub("Migration[8.0]", "Migration[7.2]"), TOPLEVEL_BINDING, name)
end
CreateLightekVault.new.migrate(:up)
CreateApplicationLaunches.new.migrate(:up)
ActiveRecord::Migration.add_column(:gatekeeper_application_templates, :lightek_application, :boolean, default: false, null: false)
AddImageBuildIdentity.new.migrate(:up)
class User < ApplicationRecord; end
%w[lightek_vault/secret lightek_vault/audit_event gatekeeper_application_template].each do |file|
  require BOOTSTRAP_ROOT.join("app/models/#{file}").to_s
end
%w[lightek_vault/master_key lightek_vault/crypto lightek_vault/policy lightek_vault/service lightek_vault/readiness
  lightek_settings/site_domain gatekeeper/hosting/access gatekeeper/hosting/github_client
  gatekeeper/hosting/github_secret_box gatekeeper/hosting/build_setup gatekeeper/hosting/image_builds
  gatekeeper/hosting/github_identity].each { |file| require BOOTSTRAP_ROOT.join("app/services/#{file}").to_s }

class HostingBootstrapTest < Minitest::Test
  KEY_ENV = %w[LIGHTEK_VAULT_MASTER_KEY LIGHTEK_VAULT_MASTER_KEY_FILE LIGHTEK_RUNTIME_ENV_FILE
    GITHUB_ACTIONS_TOKEN LIGHTEK_GITHUB_SECRET_SLUG LIGHTEK_FLEET_REGISTRY_SECRET_SLUG GATEKEEPER_APPLICATION_IMAGE_URL GATEKEEPER_FLEET_RELEASE_TOKEN]
  def setup
    @directory = Dir.mktmpdir("lightek-bootstrap-test")
    Rails.root = Pathname.new(@directory)
    @old_env = KEY_ENV.to_h { |key| [key, ENV.delete(key)] }
    LightekVault::AuditEvent.delete_all; LightekVault::Secret.delete_all
    GatekeeperApplicationTemplate.delete_all; User.delete_all
    @actor = User.create!(email_address: "operator@example.com", role: "super_admin")
  end
  def teardown
    KEY_ENV.each { |key| @old_env[key] ? ENV[key] = @old_env[key] : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
  end
  def store(slug: "linode-existing", payload: {"token" => "example-credential"}, provider: "linode", policy: {})
    LightekVault::Service.store!(name: "Test credential", slug: slug, payload: payload,
      provider: provider, access_policy: policy, requested_by: @actor.email_address)
  end
  def test_first_store_creates_one_persistent_private_key_shared_by_subsequent_crypto_instances
    secret = store
    path = LightekVault::MasterKey.key_path
    assert path.file?
    assert_equal 0, path.stat.mode & 0o077
    original = path.read
    assert_equal "example-credential", LightekVault::Crypto.new.decrypt_hash(secret).fetch("token")
    store(slug: "second")
    assert_equal original, path.read
    assert LightekVault::Readiness.call[:ready]
  end
  def test_external_master_key_is_persisted_for_web_and_worker_processes_without_rotating_it
    ENV["LIGHTEK_VAULT_MASTER_KEY"] = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
    original = ENV["LIGHTEK_VAULT_MASTER_KEY"]
    secret = store
    assert_equal original, LightekVault::MasterKey.key_path.read.strip
    ENV.delete("LIGHTEK_VAULT_MASTER_KEY")
    assert_equal "example-credential", LightekVault::Crypto.new.decrypt_hash(secret).fetch("token")
  end
  def test_existing_credentials_never_trigger_generation_of_a_replacement_key
    store
    path = LightekVault::MasterKey.key_path
    path.delete
    assert_raises(LightekVault::MasterKey::ConfigurationError) { LightekVault::MasterKey.resolve!(create_if_empty: true) }
    refute path.exist?
    assert_equal 1, LightekVault::Secret.count
  end
  def test_original_key_can_be_restored_but_wrong_key_cannot_replace_it
    secret = store
    path = LightekVault::MasterKey.key_path
    original = path.read.strip
    path.delete
    wrong = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
    assert_raises(LightekVault::Crypto::DecryptionError) { LightekVault::MasterKey.restore!(wrong) }
    refute path.exist?
    LightekVault::MasterKey.restore!(original)
    assert_equal "example-credential", LightekVault::Crypto.new.decrypt_hash(secret).fetch("token")
  end
  def test_restoring_the_verified_original_key_preserves_an_incorrect_file_as_private_backup
    secret = store
    path = LightekVault::MasterKey.key_path
    original = path.read.strip
    incorrect = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
    path.write(incorrect + "\n")
    LightekVault::MasterKey.restore!(original)
    assert_equal "example-credential", LightekVault::Crypto.new.decrypt_hash(secret).fetch("token")
    backups = path.dirname.glob(".vault-key-recovery-*")
    assert_equal 1, backups.size
    assert_equal incorrect, backups.first.read.strip
    assert_equal 0, backups.first.stat.mode & 0o077
  end
  def test_runtime_environment_file_is_read_as_data_without_executing_shell
    key = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
    path = Rails.root.join("runtime.env")
    marker = Rails.root.join("must-not-exist")
    path.write("IGNORED=$(touch #{marker})\nLIGHTEK_VAULT_MASTER_KEY=\"#{key}\"\n")
    ENV["LIGHTEK_RUNTIME_ENV_FILE"] = path.to_s
    assert_equal key, LightekVault::MasterKey.resolve!
    refute marker.exist?
  end
  def test_invalid_explicit_environment_key_does_not_silently_fall_back_or_rotate
    store
    path = LightekVault::MasterKey.key_path
    original = path.read
    ENV["LIGHTEK_VAULT_MASTER_KEY"] = "invalid"
    assert_raises(LightekVault::MasterKey::ConfigurationError) { LightekVault::MasterKey.resolve!(create_if_empty: true) }
    assert_equal original, path.read
  end
  def test_vault_policy_is_preserved_and_connected_consumer_is_audited
    secret = store(slug: "github-existing", provider: "github", policy: {"consumers" => ["ExistingConsumer"], "purposes" => ["existing-purpose"]})
    result = Gatekeeper::Hosting::BuildSetup.checkout(secret.slug, @actor)
    assert_equal "example-credential", result["token"]
    assert_equal ["ExistingConsumer", "Gatekeeper::Hosting::BuildSetup"], secret.reload.access_policy["consumers"]
    assert_equal ["existing-purpose", "image_build_setup"], secret.access_policy["purposes"]
    assert LightekVault::AuditEvent.exists?(action: "image_build_policy_connected")
  end

  class GithubDouble
    attr_reader :calls
    def initialize(secrets_ready: true)
      @calls = []
      @secrets_ready = secrets_ready
    end
    def call(method, path, body: nil, **)
      @calls << [method, path, body]
      case path
      when "/repos/Mrlightek/lightekmcg-site" then {"id" => 12345}
      when /actions\/secrets\?/ then {"secrets" => @secrets_ready ? [{"name" => "LIGHTEK_CI_APP_PRIVATE_KEY"}, {"name" => "LIGHTEK_CI_APP_ID"}] : []}
      when /actions\/variables\/LIGHTEK_CI_APP_ID/ then nil
      when /\/commits\// then {"sha" => "a" * 40}
      when "/user" then {"login" => "operator"}
      else {}
      end
    end
    def close; end
  end
  def test_setup_reuses_vault_authority_and_existing_ci_secrets_without_remote_secret_changes
    store(slug: "github-existing", provider: "github")
    client = GithubDouble.new
    Gatekeeper::Hosting::GithubClient.stub(:new, ->(*) { client }) do
      config = Gatekeeper::Hosting::BuildSetup.prepare!(actor: @actor, origin: "https://control.example.com")
      assert_equal "https://control.example.com/gatekeeper/application-images", config["callback_url"]
      assert_equal "github-existing", config["credential_slug"]
    end
    assert LightekVault::Secret.exists?(slug: Gatekeeper::Hosting::BuildSetup::SETTINGS_SLUG)
    assert LightekVault::Secret.exists?(slug: Gatekeeper::Hosting::BuildSetup::REGISTRY_SLUG)
    refute client.calls.any? { |method, path, _| [:put, :post, :patch].include?(method) && path.include?("/actions/") }
    assert_nil ENV["GATEKEEPER_APPLICATION_IMAGE_URL"]
    assert_nil ENV["GATEKEEPER_FLEET_RELEASE_TOKEN"]
  end
  def test_build_dispatch_passes_derived_callback_and_per_build_identity_without_static_token
    store(slug: "github-existing", provider: "github")
    client = GithubDouble.new
    Gatekeeper::Hosting::GithubClient.stub(:new, ->(*) { client }) do
      template = Gatekeeper::Hosting::ImageBuilds.queue!(actor: @actor, origin: "https://control.example.com",
        attributes: {"name" => "Design", "source_ref" => "develop"})
      identity = template.reload.build_identity
      assert_equal "a" * 40, identity["source_sha"]
      assert_equal "12345", identity["repository_id"]
      body = client.calls.find { |method, path, _| method == :post && path.end_with?("/dispatches") }.last
      assert_equal "develop", body[:ref]
      assert_equal identity["audience"], body[:inputs][:callback_audience]
      assert_equal "https://control.example.com/gatekeeper/application-images", body[:inputs][:callback_url]
      refute body.to_s.include?("example-credential")
    end
  end
  def test_localhost_callback_and_customer_setup_are_rejected_before_external_requests
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::BuildSetup.callback_url("http://localhost:3000") }
    @actor.update!(role: "client")
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::BuildSetup.prepare!(actor: @actor, origin: "https://control.example.com") }
  end

  def test_missing_ci_app_settings_are_synchronized_without_exposing_plaintext_private_key
    library = Fiddle.dlopen("libsodium.so.23")
    public_key = "\0".b * 32
    secret_key = "\0".b * 32
    keypair = Fiddle::Function.new(library["crypto_box_keypair"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    assert_equal 0, keypair.call(public_key, secret_key)
    payload = "private-app-key-material"
    sealed = Gatekeeper::Hosting::GithubSecretBox.encrypt(payload, Base64.strict_encode64(public_key))
    refute_includes sealed, payload
    encrypted = Base64.strict_decode64(sealed)
    plaintext = "\0".b * payload.bytesize
    open = Fiddle::Function.new(library["crypto_box_seal_open"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    assert_equal 0, open.call(plaintext, encrypted, encrypted.bytesize, public_key, secret_key)
    assert_equal payload, plaintext

    store(slug: "ci-app", provider: "github", payload: {"app_id" => "123", "private_key" => payload})
    client = GithubDouble.new(secrets_ready: false)
    original_call = client.method(:call)
    client.define_singleton_method(:call) do |method, path, **options|
      if path.end_with?("/secrets/public-key")
        {"key" => Base64.strict_encode64(public_key), "key_id" => "test-key"}
      else
        original_call.call(method, path, **options)
      end
    end
    Gatekeeper::Hosting::BuildSetup.synchronize_dependencies!(client: client, actor: @actor, dependency_slug: "ci-app", connection_slug: "unused")
    request = client.calls.find { |method, path, _| method == :put && path.end_with?("/secrets/LIGHTEK_CI_APP_PRIVATE_KEY") }
    refute_nil request
    refute_includes request.last.to_s, payload
    assert_equal "test-key", request.last[:key_id]
  end
  def test_an_ambiguous_github_connection_is_not_guessed
    store(slug: "one", provider: "github")
    store(slug: "two", provider: "github")
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::BuildSetup.connection_slug(actor: @actor) }
  end
  def test_malformed_github_app_private_key_is_an_actionable_connection_error
    client = Gatekeeper::Hosting::GithubClient.new({"app_id" => "123", "private_key" => "invalid"})
    assert_raises(Gatekeeper::Hosting::GithubClient::Error) { client.token }
  end

  def test_existing_environment_github_token_is_imported_once_as_an_encrypted_handle
    ENV["GITHUB_ACTIONS_TOKEN"] = "existing-environment-authority"
    slug = Gatekeeper::Hosting::BuildSetup.connection_slug(actor: @actor)
    assert_equal "gatekeeper-github-connection", slug
    record = LightekVault::Secret.find_by!(slug: slug)
    refute_includes record.ciphertext, "existing-environment-authority"
    assert_equal "existing-environment-authority", Gatekeeper::Hosting::BuildSetup.checkout(slug, @actor)["token"]
    assert_equal slug, Gatekeeper::Hosting::BuildSetup.connection_slug(actor: @actor)
    assert_equal 1, LightekVault::Secret.count
  end
  def test_github_app_connection_mints_and_caches_a_short_lived_installation_token
    rsa = OpenSSL::PKey::RSA.generate(2048)
    client = Gatekeeper::Hosting::GithubClient.new({"app_id" => "123", "private_key" => rsa.to_pem})
    invocations = []
    client.define_singleton_method(:call) do |method, path, **options|
      invocations << [method, path, options]
      payload, = JWT.decode(options.fetch(:bearer), rsa.public_key, true, algorithms: ["RS256"])
      raise "wrong app" unless payload["iss"] == "123"
      raise "unbounded expiry" unless payload["exp"] <= Time.now.to_i + 600
      path.end_with?("/installation") ? {"id" => 42} : {"token" => "temporary-installation-token"}
    end
    assert_equal "temporary-installation-token", client.token
    assert_equal "temporary-installation-token", client.token
    assert_equal 2, invocations.size
    assert_equal "/app/installations/42/access_tokens", invocations.last[1]
    client.close
  end

  def jwt_material
    @rsa ||= OpenSSL::PKey::RSA.generate(2048)
    @jwk ||= JWT::JWK.new(@rsa)
    [@rsa, @jwk]
  end
  def identity
    {"audience" => "https://control.example.com/build/1/random", "repository_id" => "12345", "source_sha" => "a" * 40}
  end
  def claims
    {"iss" => Gatekeeper::Hosting::GithubIdentity::ISSUER, "aud" => identity["audience"],
      "exp" => Time.now.to_i + 300, "iat" => Time.now.to_i - 1, "nbf" => Time.now.to_i - 1,
      "repository" => "Mrlightek/lightekmcg-site", "repository_id" => "12345", "sha" => "a" * 40,
      "workflow_sha" => "a" * 40, "workflow_ref" => "Mrlightek/lightekmcg-site/.github/workflows/customer-release.yml@refs/heads/develop",
      "job_workflow_ref" => "Mrlightek/lightekmcg-site/.github/workflows/application-image.yml@refs/heads/develop", "job_workflow_sha" => "a" * 40,
      "event_name" => "workflow_dispatch", "run_id" => "1234"}
  end
  def verify_claims(payload, expected: identity, key: nil)
    rsa, jwk = jwt_material
    token = JWT.encode(payload, key || rsa, "RS256", kid: jwk.kid)
    Gatekeeper::Hosting::GithubIdentity.stub(:trusted_keys, {"keys" => [jwk.export]}) do
      Gatekeeper::Hosting::GithubIdentity.verify!(token: token, identity: expected)
    end
  end
  def test_signed_github_identity_is_bound_to_repository_workflow_commit_and_specific_build
    assert_equal "1234", verify_claims(claims)["run_id"]
    assert_equal "1234", verify_claims(claims.merge("iat" => Time.now.to_i + 10))["run_id"]
    {"repository_id" => "other", "aud" => "different-build", "sha" => "b" * 40,
      "workflow_ref" => "Mrlightek/lightekmcg-site/.github/workflows/other.yml@refs/heads/develop",
      "event_name" => "pull_request", "iat" => Time.now.to_i + 60, "exp" => Time.now.to_i - 60}.each do |name, value|
      assert_raises(Gatekeeper::Hosting::GithubIdentity::Invalid) { verify_claims(claims.merge(name => value)) }
    end
    assert_raises(Gatekeeper::Hosting::GithubIdentity::Invalid) { verify_claims(claims, expected: identity.merge("run_id" => "999")) }
    assert_raises(Gatekeeper::Hosting::GithubIdentity::Invalid) { verify_claims(claims, key: OpenSSL::PKey::RSA.generate(2048)) }
  end
end
