gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'active_support/all'
require 'action_mailer'
require 'action_controller'
require 'action_controller/test_case'
require 'socket'
require 'ostruct'
require 'digest'
require 'json'
require 'logger'
ROOT = File.expand_path('../..', __dir__)
require ROOT+'/app/services/lightek_mail/transport'
require ROOT+'/app/services/lightek_mail/smtp_delivery'
require ROOT+'/app/mailers/application_mailer'
require ROOT+'/app/mailers/lightek_mail/transactional_probe_mailer'
require ROOT+'/app/mailers/passwords_mailer'
ActionMailer::Base.add_delivery_method(:lightek_smtp, LightekMail::SmtpDelivery)
ActionMailer::Base.delivery_method = :lightek_smtp
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.view_paths = [ROOT+'/app/views']
PasswordsMailer.helper do
  def edit_password_url(token) = "https://example.test/passwords/#{token}/edit"
end
module Rails
  def self.logger = Logger.new(IO::NULL)
end
module LightekVault
  class Secret
    class << self; attr_accessor :record; end
    def self.find_by(*) = record
  end
  class Service
    class << self; attr_accessor :disabled; end
    def self.checkout!(**) = raise('Mail must not check out Google credentials')
    def self.disable!(**args)
      self.disabled = args
      Secret.record.status = 'disabled'
    end
  end
end
class ApplicationController < ActionController::Base
  attr_accessor :current_user
end
module Dashboard; end
require ROOT+'/app/controllers/dashboard/mail_transport_controller'

module LocalSmtpFixture
  def start_smtp(reject: false)
    @messages = []
    @commands = []
    @server = TCPServer.new('127.0.0.1', 0)
    @previous_env = ENV.to_h.slice('LIGHTEK_MAIL_SMTP_HOST','LIGHTEK_MAIL_SMTP_PORT','LIGHTEK_MAIL_SMTP_USERNAME','LIGHTEK_MAIL_SMTP_PASSWORD')
    ENV['LIGHTEK_MAIL_SMTP_HOST'] = '127.0.0.1'
    ENV['LIGHTEK_MAIL_SMTP_PORT'] = @server.addr[1].to_s
    ENV.delete('LIGHTEK_MAIL_SMTP_USERNAME')
    ENV.delete('LIGHTEK_MAIL_SMTP_PASSWORD')
    @smtp_thread = Thread.new do
      loop do
        socket = @server.accept
        socket.write("220 fixture ESMTP\r\n")
        while (line = socket.gets)
          @commands << line
          case line
          when /\AEHLO/, /\AHELO/ then socket.write("250 fixture\r\n")
          when /\AMAIL FROM/ then socket.write(reject ? "550 sender rejected\r\n" : "250 sender accepted\r\n")
          when /\ARCPT TO/ then socket.write("250 recipient accepted\r\n")
          when /\ADATA/
            socket.write("354 send message\r\n")
            data = +''
            while (part = socket.gets) && part != ".\r\n"; data << part; end
            @messages << data
            socket.write("250 queued\r\n")
          when /\AQUIT/ then socket.write("221 bye\r\n"); break
          else socket.write("250 OK\r\n")
          end
        end
        socket.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
    @smtp_thread.report_on_exception = false
  end
  def stop_smtp
    @server&.close
    @smtp_thread&.kill
    @smtp_thread&.join
    return unless @previous_env
    %w[LIGHTEK_MAIL_SMTP_HOST LIGHTEK_MAIL_SMTP_PORT LIGHTEK_MAIL_SMTP_USERNAME LIGHTEK_MAIL_SMTP_PASSWORD].each { |key| @previous_env&.key?(key) ? ENV[key] = @previous_env[key] : ENV.delete(key) }
  end
end
class LightekTransactionalMailTest < Minitest::Test
  include LocalSmtpFixture
  def teardown = stop_smtp
  def test_probe_crosses_real_smtp_without_google_checkout
    start_smtp
    LightekMail::TransactionalProbeMailer.delivery_probe('operator@example.test','abc123').deliver_now
    assert_equal 1, @messages.size
    decoded = Mail.read_from_string(@messages.first)
    assert_equal ['operator@example.test'], decoded.to
    assert_includes decoded.subject, 'abc123'
    assert_includes decoded.body.decoded, 'abc123'
    assert @commands.any? { |command| command.start_with?('MAIL FROM:') }
  end
  def test_real_password_reset_mailer_uses_shared_smtp_and_preserves_both_parts
    start_smtp
    PasswordsMailer.reset(OpenStruct.new(email_address:'operator@example.test', password_reset_token:'fixture-token')).deliver_now
    decoded = Mail.read_from_string(@messages.fetch(0))
    assert_equal 'Reset your password', decoded.subject
    assert_includes decoded.text_part.decoded, '/passwords/fixture-token/edit'
    assert_includes decoded.html_part.decoded, '/passwords/fixture-token/edit'
    assert_equal ['no-reply@lightekmcg.com'], decoded.from
  end
  def test_smtp_preserves_blind_recipients_without_exposing_the_header
    start_smtp
    message = Mail.new(from:'no-reply@lightekmcg.com',to:'operator@example.test',bcc:'blind@example.test',subject:'Envelope check',body:'Test')
    message.delivery_method(LightekMail::SmtpDelivery)
    message.deliver!
    assert @commands.any? { |command| command.include?('RCPT TO:<blind@example.test>') }
    refute_match(/^Bcc:/i, @messages.fetch(0))
  end
  def test_smtp_failure_surfaces_without_a_fallback
    start_smtp(reject: true)
    assert_raises(Net::SMTPFatalError) { LightekMail::TransactionalProbeMailer.delivery_probe('operator@example.test','failure').deliver_now }
    assert_empty @messages
  end
  def test_default_and_old_gmail_configuration_select_lightek_smtp
    source = File.read(ROOT+'/config/environments/production.rb')
    start = source.index('  case ENV.fetch("MAIL_DELIVERY_METHOD"')
    block = source[start...source.index('  config.action_mailer.default_url_options',start)]
    previous = ENV['MAIL_DELIVERY_METHOD']
    [nil,'gmail_api','lightek_smtp'].each do |choice|
      choice ? ENV['MAIL_DELIVERY_METHOD'] = choice : ENV.delete('MAIL_DELIVERY_METHOD')
      config = OpenStruct.new(action_mailer: OpenStruct.new)
      eval(block, binding)
      assert_equal :lightek_smtp, config.action_mailer.delivery_method
    end
    ENV['MAIL_DELIVERY_METHOD'] = 'lightek_https'
    config = OpenStruct.new(action_mailer: OpenStruct.new)
    eval(block, binding)
    assert_equal :lightek_https, config.action_mailer.delivery_method
  ensure
    previous ? ENV['MAIL_DELIVERY_METHOD'] = previous : ENV.delete('MAIL_DELIVERY_METHOD')
  end
end
class MailTransportControllerTest < ActionController::TestCase
  tests Dashboard::MailTransportController
  include LocalSmtpFixture
  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get '/dashboard/mail-transport', to:'dashboard/mail_transport#show', as: :dashboard_mail_transport
      post '/dashboard/mail-transport/test', to:'dashboard/mail_transport#test_delivery'
      post '/dashboard/mail-transport/retire-gmail', to:'dashboard/mail_transport#retire_gmail'
    end
    @controller.define_singleton_method(:dashboard_mail_transport_path) { '/dashboard/mail-transport' }
    @controller.allow_forgery_protection = false
    @controller.current_user = OpenStruct.new(role:'super_admin',email_address:'operator@example.test')
    LightekVault::Secret.record = OpenStruct.new(status:'active')
    LightekVault::Secret.record.define_singleton_method(:disabled?) { status == 'disabled' }
    LightekVault::Service.disabled = nil
    start_smtp
  end
  def teardown = stop_smtp
  def test_only_operator_can_send_checks_or_retire_credentials
    @controller.current_user.role = 'white_label'
    get :show
    assert_response :forbidden
    post :test_delivery
    assert_response :forbidden
    post :retire_gmail, params: {received:'1'}
    assert_response :forbidden
    assert_empty @messages
    assert_nil LightekVault::Service.disabled
  end
  def test_probe_recipient_is_bound_to_signed_in_operator_and_receipt_is_required
    post :test_delivery, params:{recipient:'someone-else@example.test'}
    assert_response :redirect
    assert_equal ['operator@example.test'], Mail.read_from_string(@messages.fetch(0)).to
    assert @request.session[:transactional_mail_probe]['reference']
    post :retire_gmail
    assert_nil LightekVault::Service.disabled
    post :retire_gmail, params:{received:'1'}
    assert_equal 'gmail-api-production', LightekVault::Service.disabled[:slug]
    assert_equal 'operator@example.test', LightekVault::Service.disabled[:requested_by]
    assert_nil @request.session[:transactional_mail_probe]
  end
  def test_missing_stale_and_changed_route_evidence_cannot_disable_gmail
    post :retire_gmail, params:{received:'1'}
    assert_nil LightekVault::Service.disabled
    post :test_delivery
    @request.session[:transactional_mail_probe]['sent_at'] = 25.hours.ago.to_i
    post :retire_gmail, params:{received:'1'}
    assert_nil LightekVault::Service.disabled
    @request.session[:transactional_mail_probe]['sent_at'] = Time.current.to_i
    @request.session[:transactional_mail_probe]['route'] = 'different-route'
    post :retire_gmail, params:{received:'1'}
    assert_nil LightekVault::Service.disabled
  end
  def test_failed_probe_clears_earlier_evidence_and_keeps_gmail_enabled
    post :test_delivery
    stop_smtp
    start_smtp(reject:true)
    @request.session[:transactional_mail_probe]['sent_at'] = 2.minutes.ago.to_i
    post :test_delivery
    assert_response :redirect
    assert_nil @request.session[:transactional_mail_probe]
    assert_nil LightekVault::Service.disabled
    assert_equal 'active', LightekVault::Secret.record.status
  end
  def test_test_delivery_is_rate_limited
    post :test_delivery
    post :test_delivery
    assert_equal 1, @messages.size
    assert @request.session[:transactional_mail_probe]['reference']
  end
end
