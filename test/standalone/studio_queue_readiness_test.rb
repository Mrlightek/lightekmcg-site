# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "sidekiq"
require "socket"
require "tmpdir"

class StudioQueueReadinessTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @dir = Dir.mktmpdir("studio-queue-test")
    @children = []
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
    password = SecureRandom.hex(16)
    spawn_service("redis-server", "--bind", "127.0.0.1", "--port", port.to_s,
      "--dir", @dir, "--requirepass", password, "--save", "", "--appendonly", "no")
    @env = {"REDIS_URL" => "redis://:#{password}@127.0.0.1:#{port}/0"}
    redis = RedisClient.config(url: @env.fetch("REDIS_URL")).new_client
    begin
      wait_until { redis.call("PING") == "PONG" }
    ensure
      redis.close
    end
    @worker_config = File.join(@dir, "worker.rb")
    File.write(@worker_config, <<~CONFIG)
      require "pathname"
      module Rails
        def self.root = Pathname.new(__dir__)
      end
      sleep 0.5
      require #{File.join(ROOT, "config/initializers/sidekiq.rb").inspect}
    CONFIG
  end

  def teardown
    @children.reverse_each do |pid|
      Process.kill("TERM", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_waits_for_the_requested_workers_real_studio_heartbeat
    pid = start_worker(cpu_only: false)
    out, err, status = probe(pid, wait: "10")
    assert status.success?, err
    assert_equal "STUDIO_QUEUE_CONSUMER_READY\n", out

    out, err, status = probe(Process.pid)
    refute status.success?
    assert_empty out
    assert_includes err, "no Redis heartbeat for the service PID"
  end

  def test_rejects_a_worker_without_the_studio_capsule
    pid = start_worker(cpu_only: true)
    out, err, status = probe(pid, wait: "5")
    refute status.success?
    assert_empty out
    assert_includes err, "service PID heartbeat lacks the studio capsule queue"
  end

  private

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until redis_ready? { yield }
      raise "Redis fixture did not start" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end
  end

  def redis_ready?
    yield
  rescue RedisClient::CannotConnectError
    false
  end

  def spawn_service(*args)
    pid = Process.spawn(*args, out: [File.join(@dir, "services.log"), "a"], err: [:child, :out])
    @children << pid
    pid
  end

  def start_worker(cpu_only:)
    env = @env.merge("STUDIO_CPU_WORKER" => (cpu_only ? "1" : "0"))
    spawn_service(env, RUBY, Gem.bin_path("sidekiq", "sidekiq"), "-r", @worker_config, "-q", "default", "-c", "1")
  end

  def probe(pid, wait: "2")
    env = @env.merge("LIGHTEK_STUDIO_SIDEKIQ_PID" => pid.to_s, "LIGHTEK_STUDIO_QUEUE_WAIT_SECONDS" => wait)
    Open3.capture3(env, RUBY, File.join(ROOT, "script/studio/verify_queue_consumer.rb"))
  end
end
