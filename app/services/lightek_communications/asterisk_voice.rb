# frozen_string_literal: true

require "digest"
require "ipaddr"
require "resolv"
require "tempfile"
require "timeout"

module LightekCommunications
  class AsteriskVoice
    class Unavailable < VoipMs::Unavailable; end

    DIRECTORY = "/var/lib/asterisk/lightek-voice"
    CONTROL = "/usr/sbin/asterisk"
    HOST = /\A(?=.{1,253}\z)(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z0-9]+\z/i
    PASSWORD = /\ALt7[a-f0-9]{24,32}\z/

    def self.configured?
      HOST.match?(ENV["LIGHTEK_VOICE_SIP_HOST"].to_s) && deployment_proof.present?
    end

    def self.deployment_proof
      checks = %w[inbound outbound emergency].to_h do |check|
        reference = ENV["LIGHTEK_VOICE_PBX_#{check.upcase}_PROOF"].to_s
        [check, reference]
      end
      checks if checks.values.all? { |value| value.match?(/\A[a-zA-Z0-9_.:-]{1,120}\z/) }
    end

    def self.device_name(order_id)
      "lightek-#{Integer(order_id)}"
    end

    def initialize(order_id, details)
      @device = self.class.device_name(order_id)
      @trunk = "#{@device}-carrier"
      @host = details.fetch("host")
      @account = details.fetch("account")
      @trunk_password = details.fetch("trunk_password")
      @device_password = details.fetch("device_password")
      unless @host.match?(/\A[a-z0-9-]+\.voip\.ms\z/) && VoipMs::SIP_ACCOUNT.match?(@account) &&
          [@trunk_password, @device_password].all? { |password| PASSWORD.match?(password) }
        raise Unavailable, "Invalid managed phone line configuration."
      end
    end

    def prepare!
      raise Unavailable, "The dedicated PBX is unavailable." unless File.writable?(DIRECTORY) && File.executable?(CONTROL)

      command!("core waitfullybooted")
      %w[lightek-carrier lightek-devices].each do |transport|
        unless command!("pjsip show transport #{transport}").match?(/^\s*Transport:\s+#{transport}\s/)
          raise Unavailable, "The PBX has not loaded both phone transports."
        end
      end
    end

    def register!
      locked do
        path = File.join(DIRECTORY, "#{@device}.pjsip.conf")
        addresses = provider_addresses
        ingress = "carrier-#{Digest::SHA256.hexdigest(@host)[0, 12]}"
        ingress_changed = replace!(File.join(DIRECTORY, "#{ingress}.pjsip.conf"), carrier_ingress(ingress, addresses))
        changed = replace!(path, pjsip(addresses))
        result = command!("pjsip show registration #{@trunk}")
        if ingress_changed || changed || !result.include?(@trunk)
          command!("pjsip reload")
          result = command!("pjsip show registration #{@trunk}")
        end
        unless result.match?(/\bRegistered\b/)
          raise Unavailable, "The PBX is waiting for the carrier to register the trunk."
        end
      end
    end

    def connect_number!(did)
      raise Unavailable, "Invalid phone number for the PBX." unless VoipMs::NANP_NUMBER.match?("+1#{did}")

      locked do
        path = File.join(DIRECTORY, "#{@device}.extensions.conf")
        conflict = Dir.glob(File.join(DIRECTORY, "lightek-*.extensions.conf")).any? do |other|
          path != other && File.binread(other).include?("exten => #{did},1,")
        end
        raise Unavailable, "The number is already associated with a different PBX line." if conflict

        replace!(path, dialplan(did))
        command!("dialplan reload")
        ["from-lightek-carrier", "from-#{@device}"].each do |context|
          result = command!("dialplan show #{context}")
          unless result.include?("[ Context '#{context}'") && result.include?(did)
            raise Unavailable, "The PBX did not load the phone line routes."
          end
        end
      end
    end

    private

    def provider_addresses
      addresses = Resolv.getaddresses(@host).map { |address| IPAddr.new(address) }.select(&:ipv4?).uniq
      raise Unavailable, "The PBX could not resolve the carrier server." if addresses.empty?

      addresses
    rescue Resolv::ResolvError, IPAddr::InvalidAddressError
      raise Unavailable, "The PBX could not resolve the carrier server."
    end

    def locked
      File.open(File.join(DIRECTORY, ".provision.lock"), File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    rescue SystemCallError, IOError
      raise Unavailable, "The PBX could not apply the phone line configuration."
    end

    def replace!(path, contents)
      return if File.file?(path) && File.binread(path) == contents

      Tempfile.create(".voice-", DIRECTORY) do |file|
        file.chmod(0o640)
        file.write(contents)
        file.flush
        file.fsync
        File.rename(file.path, path)
      end
      true
    end

    def command!(command)
      io = IO.popen([CONTROL, "-rx", command], err: File::NULL)
      pid = io.pid
      result = Timeout.timeout(8) { io.read(64 * 1024).to_s }
      io.close
      raise Unavailable, "The PBX control connection is unavailable." unless $?.success?

      result
    rescue SystemCallError, IOError, Timeout::Error
      if io && !io.closed?
        Process.kill("KILL", pid) rescue nil
        io.close
      end
      raise Unavailable, "The PBX control connection is unavailable."
    end

    def carrier_ingress(name, addresses)
      matches = addresses.map { |address| "match=#{address}/32" }.join("\n")
      <<~CONF
        [#{name}]
        type=endpoint
        transport=lightek-carrier
        context=from-lightek-carrier
        identify_by=ip
        deny=0.0.0.0/0
        #{permits(addresses)}
        disallow=all
        allow=ulaw
        direct_media=no

        [#{name}]
        type=identify
        endpoint=#{name}
        #{matches}
      CONF
    end

    def permits(addresses)
      addresses.map { |address| "permit=#{address}/32" }.join("\n")
    end

    def pjsip(addresses)
      <<~CONF
        [#{@trunk}]
        type=registration
        transport=lightek-carrier
        outbound_auth=#{@trunk}-auth
        server_uri=sip:#{@host}:5060
        client_uri=sip:#{@account}@#{@host}:5060
        contact_user=#{@device}
        endpoint=#{@trunk}
        line=yes
        retry_interval=15
        max_random_initial_delay=1

        [#{@trunk}-auth]
        type=auth
        auth_type=userpass
        username=#{@account}
        password=#{@trunk_password}

        [#{@trunk}]
        type=endpoint
        transport=lightek-carrier
        context=from-lightek-carrier
        outbound_auth=#{@trunk}-auth
        from_domain=#{@host}
        disallow=all
        allow=ulaw
        direct_media=no
        deny=0.0.0.0/0
        #{permits(addresses)}

        [#{@device}]
        type=endpoint
        transport=lightek-devices
        context=from-#{@device}
        auth=#{@device}-auth
        aors=#{@device}
        disallow=all
        allow=ulaw
        direct_media=no
        rewrite_contact=yes
        force_rport=yes
        rtp_symmetric=yes
        media_encryption=sdes

        [#{@device}]
        type=aor
        max_contacts=1
        remove_existing=yes

        [#{@device}-auth]
        type=auth
        auth_type=userpass
        username=#{@device}
        password=#{@device_password}
      CONF
    end

    def dialplan(did)
      <<~CONF
        [from-lightek-carrier](+)
        exten => #{@device},1,Dial(PJSIP/#{@device},30)
        exten => #{did},1,Dial(PJSIP/#{@device},30)
        exten => 1#{did},1,Dial(PJSIP/#{@device},30)
        exten => +1#{did},1,Dial(PJSIP/#{@device},30)

        [from-#{@device}]
        exten => _NXXNXXXXXX,1,Goto(1\${EXTEN},1)
        exten => _+1NXXNXXXXXX,1,Goto(\${EXTEN:1},1)
        exten => _1NXXNXXXXXX,1,Set(CALLERID(num)=#{did})
         same => n,Dial(PJSIP/#{@trunk}/sip:\${EXTEN}@#{@host}:5060,60)
        exten => 911,1,Set(CALLERID(num)=#{did})
         same => n,Dial(PJSIP/#{@trunk}/sip:911@#{@host}:5060,60)
        exten => 933,1,Set(CALLERID(num)=#{did})
         same => n,Dial(PJSIP/#{@trunk}/sip:933@#{@host}:5060,60)
      CONF
    end
  end
end
