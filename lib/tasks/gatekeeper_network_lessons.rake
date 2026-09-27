namespace :gatekeeper do
  task learn_network_control: :environment do
    lessons = [
      {
        key: "GK-LESSON-GODADDY-DNS-CONTROL",
        title: "GoDaddy DNS changes use the Domains v3 record API",
        capability: "dns_management",
        symptom: "A Lightek service requires a DNS record to be created, changed, or removed.",
        cause: "Authoritative DNS state lives outside the Rails host and must be changed through the provider control plane.",
        remediation: "Use the GoDaddy Domains v3 DNS API with an allowlisted domain and audit every mutation as a Gatekeeper operation.",
        verification: "Read the record back through the API and verify external resolution after propagation.",
        metadata: { provider: "godaddy", auto_executable: true, dashboard: "/dashboard/network" }
      },
      {
        key: "GK-LESSON-FIREWALL-CONTROL",
        title: "Firewall mutations use the root-owned allowlisted helper",
        capability: "firewall_management",
        symptom: "A Lightek service requires a host port to be opened or closed.",
        cause: "Rails runs without root privileges while UFW mutation requires elevated privileges.",
        remediation: "Gatekeeper invokes lightek-firewall-control through passwordless sudo. The helper validates input and protects ports 22, 80 and 443.",
        verification: "Read UFW state after mutation and verify SSH and HTTPS remain reachable.",
        metadata: { provider: "ufw", auto_executable: true, protected_ports: [22,80,443], dashboard: "/dashboard/network" }
      }
    ]
    lessons.each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
