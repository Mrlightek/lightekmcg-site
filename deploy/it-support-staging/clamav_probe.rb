# frozen_string_literal: true

# A harmless, explicitly registered signature, only used in isolated checks.
marker = "LIGH_TE_K_BATCH_D_SCAN_CANARY_V1".b
if ARGV.include?("--signature")
  puts "Lightek.BatchD.Acceptance:0:*:#{marker.unpack1("H*")}"
  exit
end

if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
  abort "Run on the dedicated Batch D staging instance" unless Rails.root.to_s.match?(%r{\A/opt/lightek-sites/batch-d-[^/]+/})
else
  # The CI runner launches a disposable scanner on a test-only loopback port.
  module Rails
    def self.application = self
    def self.credentials = { it_remote_support: { clamd_port: 13310 } }
  end
  require_relative "../../app/services/it_services/remote_support_file_scanner"
end

scanner = ItServices::RemoteSupportFileScanner
abort "Clean document was rejected" unless scanner.clean?("Ordinary synthetic staging document.")
abort "Scanner missed the synthetic signature" if scanner.clean?(marker)
puts "ClamAV INSTREAM accepted a clean file and rejected the synthetic signature"
