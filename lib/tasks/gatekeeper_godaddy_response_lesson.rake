namespace :gatekeeper do
  desc "Teach the GoDaddy v3 DNS collection response contract"
  task learn_godaddy_dns_collection_response: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-GODADDY-DNS-COLLECTION-RESPONSE",
      title: "GoDaddy DNS list responses wrap records in items",
      capability: "dns_management",
      symptom: "The Network & Domains dashboard returns HTTP 500 with TypeError: no implicit conversion of String into Integer while rendering record[\"type\"].",
      cause: "GET /v3/domains/zones/{zone}/dns-records returns a collection object. DNS records are inside response[\"items\"]. Converting the response hash with Array(...) creates key/value pair arrays, so string-key lookup fails in the view.",
      remediation: "Normalize the provider response inside Godaddy::DnsService#records. Extract response[\"items\"], validate Array<Hash>, follow page/totalPages pagination with pageSize=100, and return only DNS record hashes.",
      verification: "Run bin/rails zeitwerk:check, confirm Godaddy::DnsService#records returns Array<Hash>, then request /dashboard/network and verify HTTP 200.",
      metadata: {
        provider: "godaddy",
        endpoint: "GET /v3/domains/zones/{zone}/dns-records",
        failure_signature: "TypeError: no implicit conversion of String into Integer",
        auto_executable: true,
        response_collection_key: "items"
      }
    )
    puts "Recorded GK-LESSON-GODADDY-DNS-COLLECTION-RESPONSE as KB article #{article.id}"
  end
end
