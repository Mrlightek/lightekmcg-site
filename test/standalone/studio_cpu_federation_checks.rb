require_relative "studio_cpu_pool_checks"
require "net/http"
require File.join(ROOT,"app/services/studio/compute/procedural_movie")
require File.join(ROOT, "lib/middleware/studio_cpu_request_limit")
ActiveRecord::Schema.define do
  create_table(:cpu_federation_orders) { |t| t.string :status; t.datetime :paid_at; t.datetime :provisioned_at }
  create_table(:lightek_reservation_peers) do |t|
    t.string :key; t.string :token_digest; t.integer :order_id; t.integer :merchant_id; t.integer :site_id; t.boolean :enabled, default: true
  end
end
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = "cpu_federation_orders"
  end
end
require File.join(ROOT, "app/models/lightek_reservations/peer")
require File.join(ROOT, "app/services/lightek_reservations/federation/client")
module LightekVault
  class Service
    def self.checkout!(**) = raise("Vault must be substituted at the credential boundary")
  end
end
require File.join(ROOT, "app/controllers/api/studio_compute_controller")
Rails.application.routes.draw do
  post "/api/reservations/federation/studio/cpu", to: "api/studio_compute#create"
  get "/api/reservations/federation/studio/cpu/:key", to: "api/studio_compute#status"
  post "/api/reservations/federation/studio/cpu/:key/resume", to: "api/studio_compute#resume"
  post "/api/reservations/federation/studio/cpu/:key/cancel", to: "api/studio_compute#cancel"
  get "/api/reservations/federation/studio/cpu/:key/files/:filename", to: "api/studio_compute#file", constraints: {filename: /movie\.mp4|scene\.blend|preview\.png/}, format: false
end
class StudioCpuFederationTest < StudioCpuPoolTest
  StudioCpuPoolTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  Broker = Studio::Compute::Federation::Broker
  Contract = Studio::Compute::Federation::Contract
  def setup
    super
    @previous_remote = ENV.to_h.slice("STUDIO_CPU_REMOTE", "STUDIO_CPU_REMOTE_PEERS")
    ENV.delete("STUDIO_CPU_REMOTE")
    @token = "#{SecureRandom.uuid}.#{SecureRandom.hex(32)}"
    @peer = LightekReservations::Peer.create!(key: @token.split('.').first, token_digest: Digest::SHA256.hexdigest(@token),
      merchant: @bob, site: @other_site, order: LightekCommerce::Order.create!(status: "fulfilled", paid_at: Time.current, provisioned_at: Time.current))
    ENV["STUDIO_CPU_REMOTE_PEERS"] = @peer.key
    @site.update!(manifest: {lightek_reservation_federation: {origin: "https://control.example", credential_slug: "test-peer", key: @peer.key}})
    @session = ActionDispatch::Integration::Session.new(StudioCpuRequestLimit.new(Rails.application))
  end
  def teardown
    %w[STUDIO_CPU_REMOTE STUDIO_CPU_REMOTE_PEERS].each { |key| ENV.delete(key) }
    @previous_remote.each { |key, value| ENV[key] = value }
    super
  end
  def operation(**values)
    op = super
    op.update!(manifest: op.manifest.deep_merge("outputs" => {"bundle" => false}))
    op
  end
  def submit(op, key: SecureRandom.hex(24)) = Broker.submit!(peer: @peer, request_key: key, manifest: op.manifest)
  def http(method, path, token: @token, data: nil)
    @session.public_send(method, path, params: data ? JSON.generate(data) : nil, headers: {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"})
    @session.response
  end
  def with_network
    # Real controller/auth/broker/JSON/stream client code, with only the socket
    # redirected into an independent HTTP integration session.
    session = @session
    adapter = Object.new
    adapter.define_singleton_method(:request) do |request, &block|
      session.public_send(request.method.downcase, request.path, params: request.body, headers: {"Authorization" => request["Authorization"], "Content-Type" => request["Content-Type"]})
      response = session.response
      result = Net::HTTPResponse::CODE_TO_OBJ.fetch(response.status.to_s).new("1.1", response.status.to_s, "test")
      result.define_singleton_method(:body) { response.body }
      result.define_singleton_method(:read_body) { |&chunks| response.body.bytes.each_slice(4096) { |slice| chunks.call(slice.pack('C*')) } }
      block ? block.call(result) : result
    end
    network = ->(*, **, &block) { block.call(adapter) }
    token = @token
    vault = ->(**values) { raise "Wrong Vault consumer" unless values[:consumer] == "LightekReservations::Federation::Client"; {"token" => token.dup} }
    LightekVault::Service.stub(:checkout!, vault) { Net::HTTP.stub(:start, network) { yield } }
  end
  def test_procedural_movie_quote_persists_the_selected_pool_and_snapshot
    ENV["STUDIO_CPU_REMOTE"]="1"
    params={scene_id:@scene.id,scene_preset:"cube",routing_mode:"remote",request_key:SecureRandom.uuid,
      procedural_script_params:{camera:"angle",lighting:"soft",motion:"spin"}}
    result=Studio::Billing::Quote.stub(:call,->(operation:,**_){operation.update!(cost_quote:{"total_cents"=>125,"currency"=>"USD"})}) do
      action("render_quote",**params)
    end
    assert_equal result,action("render_quote",**params)
    operation=StudioOperation.find(result.fetch(:operation_id))
    assert_equal "build_scene",operation.operation_type
    assert Studio::Compute::Federation::Dispatch.enabled?(operation)
    assert_equal operation.manifest,Contract.validate!(operation.manifest)
    assert_equal [512,288,120],operation.manifest.dig("scene","settings").values_at("resolution_x","resolution_y","frame_end")
    assert_equal [0,0,360],operation.manifest.dig("scene","objects",0,"definition","animation","frames",2,"rotation")
    assert_raises(ArgumentError){action("render_quote",**params.merge(routing_mode:"local"))}
    operation.update!(metadata:operation.metadata.merge("cpu_routing_mode"=>"local"))
    refute Studio::Compute::Federation::Dispatch.enabled?(operation)
  end

  def test_peer_authentication_grant_and_resource_isolation_are_enforced_over_http
    op = operation(status: "pending")
    response = http(:post, "/api/reservations/federation/studio/cpu", token: "wrong", data: {key: SecureRandom.hex(24), manifest: op.manifest})
    assert_equal 401, response.status
    ENV["STUDIO_CPU_REMOTE_PEERS"] = ""
    response = http(:post, "/api/reservations/federation/studio/cpu", data: {key: SecureRandom.hex(24), manifest: op.manifest})
    assert_equal 422, response.status
    assert_empty StudioRemoteRender.all
    ENV["STUDIO_CPU_REMOTE_PEERS"] = @peer.key
    row = submit(op)
    second_token = "#{SecureRandom.uuid}.#{SecureRandom.hex(32)}"
    second = LightekReservations::Peer.create!(key: second_token.split('.').first, token_digest: Digest::SHA256.hexdigest(second_token), merchant: @alice, site: @site, order: @peer.order)
    ENV["STUDIO_CPU_REMOTE_PEERS"] += ",#{second.key}"
    assert_equal 404, http(:get, "/api/reservations/federation/studio/cpu/#{row.request_key}", token: second_token).status
    @peer.update!(enabled: false)
    assert_equal 401, http(:get, "/api/reservations/federation/studio/cpu/#{row.request_key}").status
  end
  def test_submit_is_idempotent_bounded_and_rejects_changed_snapshot
    op = operation(status: "pending"); key = SecureRandom.hex(24)
    first = submit(op, key: key)
    assert_equal first.id, submit(op, key: key).id
    assert_equal 1, StudioRemoteRender.count
    changed = op.manifest.deep_dup; changed["scene"]["settings"]["world_strength"] = 0.7
    assert_raises(ArgumentError) { Broker.submit!(peer: @peer, request_key: key, manifest: changed) }
    submit(op)
    assert_raises(ArgumentError) { submit(op) }
    assert_equal 2, StudioRemoteRender.count
  end
  def test_resume_respects_admission_limit_and_cancel_closes_failed_work
    row = submit(operation)
    row.studio_operation.update!(status: "failed")
    submit(operation)
    submit(operation)
    assert_raises(ArgumentError) { Broker.resume!(row) }
    assert_equal "failed", row.studio_operation.reload.status
    Broker.cancel!(row)
    assert_equal "cancelled", row.studio_operation.reload.status
    assert_raises(ArgumentError) { Broker.resume!(row) }
  end
  def test_reordered_json_is_the_same_snapshot_and_failed_enqueue_can_retry
    op = operation
    key = SecureRandom.hex(24)
    row = submit(op, key: key)
    manifest = op.manifest.to_a.reverse.to_h
    assert_equal row.id, Broker.submit!(peer: @peer, request_key: key, manifest: manifest).id
    row.update!(enqueued_at: nil)
    ExecuteStudioOperationJob.stub(:perform_later, ->(*) { raise "Queue unavailable" }) do
      assert_raises(RuntimeError) { Broker.submit!(peer: @peer, request_key: key, manifest: manifest) }
    end
    assert_nil row.reload.enqueued_at
    Broker.submit!(peer: @peer, request_key: key, manifest: manifest)
    assert row.reload.enqueued_at
    assert_equal 1, StudioRemoteRender.count
  end
  def test_tls_gate_and_oversized_json_are_rejected_before_admission
    Rails.env.stub(:production?, true) do
      assert_equal 426, http(:post, "/api/reservations/federation/studio/cpu", data: {}).status
    end
    response = http(:post, "/api/reservations/federation/studio/cpu", data: {padding: "x" * (1.megabyte + 1)})
    assert_equal 413, response.status
    assert_empty StudioRemoteRender.all
  end
  def test_revoked_peer_stops_a_leased_central_attempt_at_heartbeat
    row = submit(operation)
    lease = Studio::Compute::Lease.claim!(row.studio_operation)
    lease.run do
      @peer.update!(enabled: false)
      assert_raises(ArgumentError) { Studio::Compute::Lease.heartbeat! }
    end
    lease.release!
  end
  def test_inflight_receipt_keeps_remote_routing_and_rejects_changed_connection
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    ENV.delete("STUDIO_CPU_REMOTE")
    assert Studio::Compute::Federation::Dispatch.enabled?(op.reload)
    @site.update!(manifest: @site.manifest.deep_merge("lightek_reservation_federation" => {"origin" => "https://other.example"}))
    assert_raises(ArgumentError) { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal 1, StudioRemoteRender.count
    assert_equal "failed", op.reload.status
  end
  def test_capacity_backpressure_waits_and_later_admits_without_a_new_checkout
    ENV["STUDIO_CPU_REMOTE"] = "1"
    operations = 3.times.map { operation(status: "pending") }
    with_network { operations.each { |op| ExecuteStudioOperationJob.perform_now(op.id) } }
    waiting = operations.last.reload
    assert_equal "pending", waiting.status
    assert_equal "waiting_for_remote_capacity", waiting.metadata.dig("cpu_render_progress", "phase")
    assert_equal 2, StudioRemoteRender.count
    Broker.cancel!(StudioRemoteRender.first)
    with_network { ExecuteStudioOperationJob.perform_now(waiting.id) }
    assert_equal 3, StudioRemoteRender.count
    assert_equal "pending", waiting.reload.status
    assert_equal 1, DymondBank::Transaction.where(payable: waiting).count
  end
  def test_explicit_paid_resume_recovers_a_failed_central_attempt_through_http
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    row = StudioRemoteRender.first
    row.studio_operation.update!(status: "failed")
    op.reload.update!(status: "failed")
    key = op.metadata.dig("remote_cpu", "key")
    action("render_resume", operation_id: op.id)
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "pending", op.reload.status
    assert_equal "pending", row.studio_operation.reload.status
    assert_equal key, op.metadata.dig("remote_cpu", "key")
    assert_equal 1, StudioRemoteRender.count
    assert_equal 1, DymondBank::Transaction.where(payable: op).count
    response = http(:get, "/api/reservations/federation/studio/cpu/#{key}")
    assert_equal 200, response.status
    assert_equal key, JSON.parse(response.body)["key"]
  end
  def test_streamed_request_limit_stops_before_json_parsing_without_content_length
    reads = []
    input = Object.new
    input.define_singleton_method(:read) { |length| reads << length; "x" * length }
    middleware = StudioCpuRequestLimit.new(->(_) { flunk "Oversized body reached Rails" })
    status, = middleware.call("PATH_INFO" => "/api/reservations/federation/studio/cpu", "rack.input" => input)
    assert_equal 413, status
    assert_equal [1.megabyte + 1], reads
  end
  def test_contract_rejects_paths_native_sources_unsupported_controls_and_unbounded_frames
    op = operation
    variants = [
      ->(m) { m["native_template_path"] = "/etc/passwd" },
      ->(m) { m["scene"]["settings"]["native_blender_asset_id"] = 123 },
      ->(m) { m["scene"]["settings"]["frame_end"] = 2401 },
      ->(m) { m["scene"]["settings"]["resolution_x"] = 1920 },
      ->(m) { m["scene"]["objects"] = [{"name" => "Imported", "type" => "imported_asset", "definition" => {"asset_path" => "/etc/passwd"}}] },
      ->(m) { m["scene"]["objects"] = [{"name" => "Cube", "type" => "cube", "definition" => {"authoring_commands" => []}}] }
    ]
    variants.each { |change| manifest = op.manifest.deep_dup; change.call(manifest); assert_raises(ArgumentError) { Contract.validate!(manifest) } }
    assert_empty StudioRemoteRender.all
  end
  def test_cancel_resume_and_revocation_preserve_the_same_central_attempt_without_bank_transactions
    row = submit(operation)
    operation = row.studio_operation
    operation.update!(status: "failed")
    before = DymondBank::Transaction.count
    assert_equal operation.id, Broker.resume!(row).studio_operation_id
    assert_equal "pending", operation.reload.status
    Broker.cancel!(row)
    assert_equal "cancelled", operation.reload.status
    assert_raises(ArgumentError) { Broker.resume!(row) }
    assert_equal before, DymondBank::Transaction.count
    @peer.update!(enabled: false)
    assert_raises(ArgumentError) { Broker.status(row) }
  end
  def test_client_refuses_unpaid_remote_work_and_does_not_call_blender
    op = operation(status: "pending", paid: false)
    ENV["STUDIO_CPU_REMOTE"] = "1"
    assert_raises(ArgumentError) { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "failed", op.reload.status
    assert_empty StudioRemoteRender.all
  end
  def test_unsupported_remote_scene_is_rejected_before_quote_or_checkout
    operation(status: "pending")
    @scene.update!(settings: @scene.settings.merge("native_blender_asset_id" => 99))
    ENV["STUDIO_CPU_REMOTE"] = "1"
    count = StudioOperation.count
    assert_raises(ArgumentError) { action("render_quote", scene_id: @scene.id, output: "movie") }
    assert_equal count, StudioOperation.count
    assert_empty StudioRemoteRender.all
  end
  def test_lost_submit_response_reuses_key_and_does_not_enqueue_duplicate_central_work
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    connection = LightekReservations::Federation::Client.new(@site)
    wrapper = Object.new
    wrapper.define_singleton_method(:request) do |*args, **options|
      connection.request(*args, **options)
      raise IOError, "Connection lost after server accepted the request"
    end
    with_network do
      Studio::Compute::Federation::Dispatch.stub(:client, wrapper) do
        assert_raises(IOError) { ExecuteStudioOperationJob.perform_now(op.id) }
      end
    end
    assert_equal "failed", op.reload.status
    key = op.metadata.fetch("remote_cpu").fetch("key")
    row = StudioRemoteRender.find_by!(request_key: key)
    count = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:args] == [row.studio_operation_id] }
    action("render_resume", operation_id: op.id)
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal key, op.reload.metadata.dig("remote_cpu", "key")
    assert_equal 1, StudioRemoteRender.count
    assert_equal count, ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:args] == [row.studio_operation_id] }
    assert_equal 1, DymondBank::Transaction.where(payable: op).count
  end
  def test_cancelled_client_poll_cancels_its_central_attempt
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    op.update!(status: "cancelled")
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "cancelled", op.reload.status
    assert_equal "cancelled", StudioRemoteRender.first.studio_operation.status
  end
  def test_bad_transfer_checksum_never_publishes_a_completed_operation
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    key = SecureRandom.hex(24)
    op.update!(metadata: {"remote_cpu" => {"key" => key, "status" => "running"}})
    data = "movie bytes"
    client = Object.new
    client.define_singleton_method(:request) { |*args, **options| {"key" => key, "status" => "completed", "files" => [{"filename" => "movie.mp4", "bytes" => data.bytesize, "sha256" => Digest::SHA256.hexdigest(data)}]} }
    client.define_singleton_method(:download_cpu_file) { |io:, **| io.write("wrong bytes"); {"bytes" => 11, "sha256" => Digest::SHA256.hexdigest("wrong bytes")} }
    Studio::Compute::Federation::Dispatch.stub(:client, client) do
      assert_raises(ArgumentError) { ExecuteStudioOperationJob.perform_now(op.id) }
    end
    assert_equal "failed", op.reload.status
    assert_empty op.artifacts
  end
  def test_real_cross_installation_protocol_returns_verified_movie_to_original_paid_operation
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"] == "1"
    @scene.scene_objects.create!(name: "Procedural cube", object_type: "cube", definition: {location: [0,0,0], rotation: [0,0,0], scale: [1,1,1]})
    op = operation(status: "pending")
    ENV["STUDIO_CPU_REMOTE"] = "1"
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "pending", op.reload.status
    assert_equal 1, StudioRemoteRender.count
    row = StudioRemoteRender.first
    refute_equal op.id, row.studio_operation_id
    assert_equal @other_site.id, row.studio_operation.studio_project.site_id
    Rails.stub(:root, Pathname(ROOT)) { ExecuteStudioOperationJob.perform_now(row.studio_operation_id) }
    assert_equal "completed", row.studio_operation.reload.status
    with_network { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "completed", op.reload.status
    artifact = op.artifacts.find_by!(filename: "movie.mp4")
    assert_equal "video", artifact.kind
    assert artifact.file.blob.byte_size > 100
    assert_equal 1, DymondBank::Transaction.where(payable: op).count
    assert_equal 0, DymondBank::Transaction.where(payable: row.studio_operation).count
    ids = op.artifacts.pluck(:id)
    ExecuteStudioOperationJob.perform_now(op.id)
    assert_equal ids, op.artifacts.pluck(:id)
  end
end
