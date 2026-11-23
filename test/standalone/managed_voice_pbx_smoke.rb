# frozen_string_literal: true

require "fileutils"
require "open3"
require "socket"
require "tmpdir"

require_relative "../../app/services/lightek_communications/voip_ms"
require_relative "../../app/services/lightek_communications/asterisk_voice"

pbx_type = LightekCommunications::AsteriskVoice
configs = File.expand_path("../../deploy/communications/pbx", __dir__)

def command!(config, command)
  output, status = Open3.capture2e("/usr/sbin/asterisk", "-C", config, "-rx", command)
  raise output unless status.success?
  output
end

Dir.mktmpdir("managed-voice-smoke-") do |fixture|
  %w[etc keys lines spool run log db].each { |folder| Dir.mkdir(File.join(fixture, folder)) }
  module_path = Dir.glob("/usr/lib/*/asterisk/modules").first || "/usr/lib/asterisk/modules"
  config = File.join(fixture, "asterisk.conf")
  File.write(config, <<~CONF)
    [directories]
    astetcdir => #{fixture}/etc
    astmoddir => #{module_path}
    astvarlibdir => #{fixture}/db
    astdbdir => #{fixture}/db
    astdatadir => /var/lib/asterisk
    astspooldir => #{fixture}/spool
    astrundir => #{fixture}/run
    astlogdir => #{fixture}/log
  CONF
  %w[pjsip extensions modules].each do |name|
    contents = File.read(File.join(configs, "#{name}.conf")).gsub("/var/lib/asterisk/lightek-voice", "#{fixture}/lines")
      .gsub("0.0.0.0:506", "127.0.0.1:1606").gsub("/etc/asterisk/lightek", "#{fixture}/keys")
    File.write(File.join(fixture, "etc", "#{name}.conf"), contents)
  end
  raise "TLS fixture generation failed" unless system("openssl", "req", "-x509", "-newkey", "rsa:2048",
    "-keyout", "#{fixture}/keys/tls-key.pem", "-out", "#{fixture}/keys/tls-fullchain.pem", "-days", "1",
    "-nodes", "-subj", "/CN=localhost", out: File::NULL, err: File::NULL)

  carrier = UDPSocket.new
  carrier.bind("127.0.0.1", 0)
  carrier_port = carrier.addr[1]
  received_register = Queue.new
  registrar = Thread.new do
    loop do
      packet, source = carrier.recvfrom(16_384)
      first, *headers = packet.split("\r\n")
      next unless first.start_with?("REGISTER ")
      response = headers.grep(/\A(?:Via|From|To|CSeq|Call-ID|Contact):/i)
      received_register << first
      carrier.send((["SIP/2.0 200 OK"] + response + ["Expires: 300", "Content-Length: 0", "", ""]).join("\r\n"),
        0, source[3], source[1])
    end
  rescue IOError
    # The socket is closed when the smoke test ends.
  end

  log = File.join(fixture, "asterisk.log")
  pid = spawn("/usr/sbin/asterisk", "-C", config, "-f", "-vv", out: log, err: [:child, :out])
  begin
    pbx_type.send(:remove_const, :DIRECTORY)
    pbx_type.const_set(:DIRECTORY, File.join(fixture, "lines"))
    pbx = pbx_type.new(42, { "host" => "fixture.voip.ms", "account" => "123456_fixture",
      "trunk_password" => "Lt7#{'0' * 24}", "device_password" => "Lt7#{'1' * 32}" })
    pbx.define_singleton_method(:provider_addresses) { ["127.0.0.1"] }
    pbx.define_singleton_method(:replace!) do |path, contents|
      super(path, contents.gsub("fixture.voip.ms:5060", "127.0.0.1:#{carrier_port}").gsub("@fixture.voip.ms", "@127.0.0.1"))
    end
    pbx.define_singleton_method(:command!) { |command| Object.new.send(:command!, config, command) }

    20.times do |attempt|
      begin
        pbx.register!
        break
      rescue LightekCommunications::AsteriskVoice::Unavailable, RuntimeError
        raise if attempt == 19
        sleep 1
      end
    end

    pbx.connect_number!("2125550123")
    raise "No SIP REGISTER reached the fixture" if received_register.empty?
    raise "Missing SRTP customer endpoint" unless command!(config, "pjsip show endpoint lightek-42").match?(/media_encryption\s*:\s*sdes/)
    puts "PBX registered with the simulated carrier and loaded inbound, outbound, and emergency routes."
  rescue StandardError
    warn File.read(log).lines.last(50).join if File.exist?(log)
    raise
  ensure
    Process.kill("TERM", pid) rescue nil
    Process.wait(pid)
    carrier.close
    registrar.join
  end
end
