# frozen_string_literal: true
require 'net/http'
require 'resolv'
require 'ipaddr'
require 'digest'
require 'nokogiri'
module NevaehOs
  # HTTPS only, public IPv4 only, DNS pinned per hop; source text is inert data.
  class WebDocument
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4].map { |s| IPAddr.new(s) }.freeze
    MAX_BYTES = 1_000_000
    def self.public_address!(address)
      ip = IPAddr.new(address)
      raise ArgumentError, 'Only public IPv4 documentation hosts are supported' unless ip.ipv4? && BLOCKED.none? { |net| net.include?(ip) }
      address
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, 'Invalid documentation host'
    end
    def self.fetch(url)
      4.times do
        uri = URI.parse(url)
        raise ArgumentError, 'Use a public HTTPS documentation URL on port 443' unless uri.is_a?(URI::HTTPS) && uri.host && uri.port == 443 && !uri.userinfo && url.bytesize <= 2000
        addresses = Resolv.getaddresses(uri.host)
        raise ArgumentError, 'Documentation host has no address' if addresses.empty?
        # Reject mixed public/private answers rather than selecting a convenient answer.
        addresses.each { |address| public_address!(address) }
        http = Net::HTTP.new(uri.host, 443, nil)
        http.ipaddr = addresses.first
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 8
        http.write_timeout = 5
        body = +''
        redirect = nil
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        http.start do |connection|
          connection.request(Net::HTTP::Get.new(uri.request_uri, {'User-Agent'=>'Lightek-Nevaeh-Documentation/1.0', 'Accept'=>'text/html,text/plain', 'Accept-Encoding'=>'identity'})) do |response|
            if response.is_a?(Net::HTTPRedirection)
              redirect = URI.join(url, response.fetch('location')).to_s
              next
            end
            raise ArgumentError, "Documentation returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
            raise ArgumentError, 'Only HTML or plain text documentation is supported' unless response['content-type'].to_s.match?(%r{\Atext/(html|plain)(?:;|\z)}i)
            response.read_body do |chunk|
              body << chunk
              raise ArgumentError, 'Documentation exceeds 1 MB' if body.bytesize > MAX_BYTES
              raise ArgumentError, 'Documentation fetch timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 15
            end
          end
        end
        if redirect
          url = redirect
          next
        end
        doc = Nokogiri::HTML(body.force_encoding('UTF-8').scrub)
        title = doc.at_css('title')&.text.to_s.strip.presence || uri.host
        doc.css('script,style,nav,footer,iframe,form,noscript').remove
        doc.css('h1,h2,h3,h4,h5,h6').each { |heading| heading.content = "\n#{'#' * heading.name[1].to_i} #{heading.text}\n" }
        doc.css('p,li,pre').each { |block| block.content = "\n#{block.text}\n" }
        text = (doc.at_css('main,article') || doc.at_css('body') || doc).text.gsub(/[\t ]+/, ' ').gsub(/\n\s*\n+/, "\n\n").strip[0,100000]
        raise ArgumentError, 'No readable documentation found' if text.blank?
        return {url: url, title: title[0,200], body: text, sha256: Digest::SHA256.hexdigest(text)}
      end
      raise ArgumentError, 'Too many documentation redirects'
    rescue URI::InvalidURIError, SocketError, Resolv::ResolvError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
      raise ArgumentError, "Documentation could not be retrieved (#{error.class.name})"
    end
  end
end
