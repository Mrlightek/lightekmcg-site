# Verify the real worker configuration while the default queue is blocked.
require 'sidekiq'
require 'pathname'
require 'tmpdir'
require 'rbconfig'
ROOT=File.expand_path('../..',__dir__)
class VoiceQueueBlocker
  include Sidekiq::Job
  sidekiq_options queue:'default',retry:false
  def perform(key)
    Sidekiq.redis { |redis| redis.call('SET',key+':blocked','1') }
    sleep 20
  end
end
class VoiceQueueProbe
  include Sidekiq::Job
  sidekiq_options queue:'nevaeh_voice',retry:false
  def perform(key)
    Sidekiq.redis { |redis| redis.call('SET',key+':voice','1') }
  end
end
class StudioQueueProbe
  include Sidekiq::Job
  sidekiq_options queue: 'studio', retry: false
  def perform(key)
    Sidekiq.redis { |redis| redis.call('SET', key + ':studio', '1') }
  end
end
if ENV['NEVAEH_QUEUE_TEST_SERVER']=='1'
  module Rails
    def self.root = Pathname(ENV.fetch('NEVAEH_QUEUE_TEST_ROOT'))
  end
  load File.join(ROOT,'config/initializers/sidekiq.rb')
else
  require 'minitest/autorun'
  class NevaehVoiceQueueTest < Minitest::Test
    def test_voice_and_studio_run_while_default_queue_is_occupied
      Sidekiq.configure_client { |config| config.redis={url:ENV.fetch('REDIS_URL')} }
      key='nevaeh-voice-test:'+Process.pid.to_s
      Dir.mktmpdir('voice-queue-') do |root|
        log=File.join(root,'sidekiq.log')
        environment={'NEVAEH_QUEUE_TEST_SERVER'=>'1','NEVAEH_QUEUE_TEST_ROOT'=>root,'STUDIO_CPU_WORKER'=>'0'}
        code='require "sidekiq/cli"; Sidekiq::CLI.instance.parse(ARGV); Sidekiq::CLI.instance.run'
        pid=Process.spawn(environment,RbConfig.ruby,'-e',code,'--','-r',File.expand_path(__FILE__),'-q','default','-c','1','-t','1',chdir:root,out:log,err:[:child,:out])
        begin
          VoiceQueueBlocker.perform_async(key)
          wait_for(key+':blocked',log)
          started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          VoiceQueueProbe.perform_async(key)
          StudioQueueProbe.perform_async(key)
          wait_for(key+':voice',log)
          wait_for(key+':studio',log)
          probe = File.join(ROOT, 'script/studio/verify_queue_consumer.rb')
          assert system({'LIGHTEK_STUDIO_SIDEKIQ_PID' => pid.to_s}, RbConfig.ruby,
            '-r', 'sidekiq', '-e', 'Sidekiq.configure_client { |config| config.redis = {url: ENV.fetch("REDIS_URL")} }; load ARGV.fetch(0)', probe)
          assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,:<,8
          assert_equal '1',Sidekiq.redis { |redis| redis.call('GET',key+':blocked') }
        ensure
          Process.kill('TERM',pid) rescue nil
          Process.wait(pid) rescue nil
          Sidekiq.redis { |redis| redis.call('DEL',key+':blocked',key+':voice',key+':studio') }
        end
      end
    end
    def wait_for(key,log)
      deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+8
      until Sidekiq.redis { |redis| redis.call('GET',key) }=='1'
        flunk "Worker did not execute #{key}: #{File.read(log)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
        sleep 0.05
      end
    end
  end
end
