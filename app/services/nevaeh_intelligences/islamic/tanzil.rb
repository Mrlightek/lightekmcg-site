# frozen_string_literal: true
require 'net/http'
require 'uri'
module NevaehIntelligences
  module Islamic
    module Tanzil
      DOWNLOAD = 'https://tanzil.net/pub/download/index.php?agree=true&quranType=uthmani&marks=true&sajdah=true&tatweel=true&outType=txt-2'.freeze
      LICENSE = <<~TEXT.freeze
        Tanzil Quran Text
        Copyright (C) 2007-2021 Tanzil Project
        License: Creative Commons Attribution 3.0

        This copy of the Quran text is carefully produced, highly
        verified and continuously monitored by a group of specialists
        in Tanzil Project.

        TERMS OF USE:
        - Permission is granted to copy and distribute verbatim copies
          of this text, but CHANGING IT IS NOT ALLOWED.
        - This Quran text can be used in any website or application,
          provided that its source (Tanzil Project) is clearly indicated,
          and a link is made to tanzil.net to enable users to keep
          track of changes.
        - This copyright notice shall be included in all verbatim copies
          of the text, and shall be reproduced appropriately in all files
          derived from or containing substantial portion of this text.

        Please check updates at: http://tanzil.net/updates/
      TEXT
      module_function
      def import!(actor:, training_permitted: false, permission_evidence: '')
        Importer.authorize!(actor)
        uri = URI(DOWNLOAD)
        body = +''
        # Fixed official endpoint only. No caller-controlled URLs or redirects.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 25
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            raise ArgumentError, 'Tanzil download unavailable; use the upload option' unless response.is_a?(Net::HTTPSuccess)
            response.read_body do |chunk|
              raise ArgumentError, 'Tanzil download exceeded its time or size budget' if body.bytesize + chunk.bytesize > Importer::MAX_BYTES || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              body << chunk
            end
          end
        end
        body.force_encoding(Encoding::UTF_8)
        raise ArgumentError, 'Tanzil returned invalid UTF-8' unless body.valid_encoding?
        document = Importer.tanzil_document(text: body, license: LICENSE, training_permitted: training_permitted, permission_evidence: permission_evidence)
        Importer.import!(raw: JSON.generate(document), actor: actor)
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError
        raise ArgumentError, 'Tanzil download unavailable; retry or use the upload option'
      end
    end
  end
end
