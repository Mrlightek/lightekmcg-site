#!/bin/bash
set -e
cat > /tmp/seed_products.rb << 'RUBY_EOF'
# frozen_string_literal: true
# Seeds the 8 modules that were hardcoded in the original store mockup.
# Idempotent — safe to run more than once, won't duplicate.

DATA = [
  {
    sku: "SKU-001", name: "BANK MODULE", department: "Treasury · Finance", icon: "🏦", color: "#18B870",
    wholesale_price: 840, ministry_engine: true,
    description: "Full neobank deployment. Accounts, lending, transfers, financial coaching. Community Credit Pool included. Constitutionally compliant under Articles II and VIII.",
    includes_json: ["Full account management suite (checking, savings, credit)", "Lending engine with Community Credit Pool", "DYMOND BANK-powered financial coaching layer", "Article VIII zero-cost access tier for qualifying citizens", "Ministry Engine Economic Equity Override protocol", "White-label branding — your name on every surface"],
    specs_json: { "deployment" => "3 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "API + Webhook", "update" => "Automatic · Included", "support" => "24/7 · Dedicated" }
  },
  {
    sku: "SKU-008", name: "CHURCH MODULE", department: "Faith · Ministry", icon: "✝", color: "#C09018",
    wholesale_price: 480, ministry_engine: true,
    description: "Complete faith community platform. Live streaming, sermon notes, prayer wall, tithe collection, Bible study groups, ordination network. Ministry Engine fully embedded.",
    includes_json: ["Live service streaming with up to 50K concurrent viewers", "Sermon notes, passages, and save-to-library feature", "Interactive prayer wall with community responses", "Tithe and offering collection linked to BANK module", "Bible study group management with discussion threads", "Ordination network access — ministers bookable via BOOKING module"],
    specs_json: { "deployment" => "2 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "BANK + BOOKING + WELLNESS", "update" => "Automatic", "support" => "24/7 + Faith Advisor" }
  },
  {
    sku: "SKU-014", name: "STREAMING MODULE", department: "Culture · Media", icon: "📺", color: "#CC1818",
    wholesale_price: 1200, ministry_engine: false,
    description: "Full streaming platform for original content. Video library, live broadcast, creator dashboard, royalty tracking, post-episode podcast integration. DYMOND+ white-labeled.",
    includes_json: ["Unlimited video library with adaptive bitrate streaming", "Live broadcast engine — up to 100K concurrent viewers", "Creator dashboard with full royalty tracking and catalog ownership", "Post-episode podcast link integration", "Attribution enforcement — Article VI compliance built in", "White-label — your platform name, logo, domain"],
    specs_json: { "deployment" => "5 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "STUDIO + PODCAST + SOCIAL", "update" => "Automatic", "support" => "24/7 + Media Specialist" }
  },
  {
    sku: "SKU-003", name: "INSTITUTE MODULE", department: "Education", icon: "🎓", color: "#146414",
    wholesale_price: 600, ministry_engine: false,
    description: "Full e-learning platform with curriculum management, enrollment, certifications, and flywheel loan bridge to Bank module. Graduates earn, loans repay automatically.",
    includes_json: ["Course creation and curriculum management tools", "Enrollment flow with payment integration", "Certification engine with verifiable credentials", "BANK loan bridge — flywheel cycle automation", "Grant seat management (min 20% of enrollment capacity free)", "Analytics dashboard — graduate outcomes and impact tracking"],
    specs_json: { "deployment" => "3 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "BANK + STUDIO + COMMUNITY", "update" => "Automatic", "support" => "24/7 + Education Advisor" }
  },
  {
    sku: "SKU-009", name: "WELLNESS MODULE", department: "Health · Wellness", icon: "🌿", color: "#18A870",
    wholesale_price: 360, ministry_engine: true,
    description: "Mental health, meditation, recovery protocols, pastoral counseling pathway. Faith-based wellness integrated with Church and Fit modules. Body as Temple protocol active.",
    includes_json: ["Mental health resource library and provider directory", "Guided meditation and mindfulness programs", "Body as Temple protocol — faith-integrated fitness pathway", "Pastoral counseling booking bridge to CHURCH module", "Recovery protocol suite — community-based support groups", "Mood and wellness tracking with privacy-first data model"],
    specs_json: { "deployment" => "2 business days", "citizens" => "Unlimited", "uptime" => "99.99% SLA", "integration" => "CHURCH + FIT + MATCH", "update" => "Automatic", "support" => "24/7 + Wellness Advisor" }
  },
  {
    sku: "SKU-019", name: "MATCH MODULE", department: "Family Affairs", icon: "💑", color: "#CC2870",
    wholesale_price: 480, ministry_engine: true,
    description: "Compatibility matching with full marriage journey pipeline. Grace-First protocol, pastor counseling bridge, Bank financial readiness check, ordination network.",
    includes_json: ["Grace-First matching algorithm — Ministry Engine protocol", "Pre-marital pastoral counseling booking integration", "BANK financial readiness assessment for matched couples", "Real estate search integration for first homes", "BOOKING module — ordination and ceremony scheduling", "Marriage journey milestone tracking — all 6 stages"],
    specs_json: { "deployment" => "2 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "CHURCH + BANK + RE + BOOKING", "update" => "Automatic", "support" => "24/7 · Family Advisor" }
  },
  {
    sku: "SKU-015", name: "STUDIO MODULE", department: "Culture · Production", icon: "🎬", color: "#CC4040",
    wholesale_price: 720, ministry_engine: false,
    description: "Professional content creation suite. Video production, audio tools, collaboration workspace, distribution pipeline. All content owned by creator per Article I.",
    includes_json: ["Professional video editing and production environment", "Multi-track audio suite with voice isolation", "Real-time collaboration workspace for distributed teams", "One-click distribution to STREAMING, PODCAST, and SOCIAL modules", "Creator rights vault — all content ownership documented", "Attribution tracking — Article VI compliance embedded"],
    specs_json: { "deployment" => "3 business days", "citizens" => "Unlimited", "uptime" => "99.97% SLA", "integration" => "STREAMING + PODCAST + SOCIAL", "update" => "Automatic", "support" => "24/7 + Production Specialist" }
  },
  {
    sku: "SKU-020", name: "COMMUNITY MODULE", department: "Community · Social", icon: "👥", color: "#5828A8",
    wholesale_price: 360, ministry_engine: true,
    description: "Full community platform. Groups, events, mutual aid feeds, announcements, notifications. Sets social architecture included. Constitution Article I–V rights protected.",
    includes_json: ["Group creation and management — unlimited groups", "Event creation with BOOKING integration", "Mutual aid request and response board", "Community announcements and notification system", "Sets neighborhood architecture — territory-based community layers", "Constitutional rights banner — Article I–V always visible to citizens"],
    specs_json: { "deployment" => "1 business day", "citizens" => "Unlimited", "uptime" => "99.99% SLA", "integration" => "SOCIAL + SETS + BOOKING + MESSAGES", "update" => "Automatic", "support" => "24/7 · Community Advisor" }
  }
].freeze

DATA.each do |row|
  product = DymondCatalog::Product.find_or_initialize_by(sku: row[:sku])
  product.assign_attributes(row.except(:sku))
  product.active = true
  product.save!
  puts "#{product.persisted? ? 'saved' : 'FAILED'}: #{product.sku} — #{product.name}"
end

puts ""
puts "Total products: #{DymondCatalog::Product.count}"
RUBY_EOF

cd ~/Desktop/Development/lightekmcg-site
bin/rails runner /tmp/seed_products.rb
rm /tmp/seed_products.rb
