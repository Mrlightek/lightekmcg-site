# frozen_string_literal: true
# Run: SITE_HOST=192.168.64.2 bin/rails runner script/commercial_cms_content_seed.rb
# Apply: RAILS_ENV=development SITE_HOST=192.168.64.2 APPLY=1 bin/rails runner script/commercial_cms_content_seed.rb
abort 'BLOCKED: development only' unless Rails.env.development?

host = ENV.fetch('SITE_HOST', '').strip
abort 'BLOCKED: set SITE_HOST to an exact existing Dymond Site host' if host.empty?
apply = ENV['APPLY'] == '1'
site = DymondSite::Site.find_by(host: host)
abort "BLOCKED: CMS site not found host=#{host}" unless site

# Only registered section kinds with JSON keys confirmed on the existing Lightek site.
required = %w[hero rich_text cta_banner]
abort 'BLOCKED: section kinds missing from registry' unless required.all? { |kind| DymondSite::SectionRegistry.find(kind) }
abort 'BLOCKED: expected CMS schema unavailable' unless (DymondSite::Section.column_names & %w[kind data position page_id]).sort == %w[data kind page_id position].sort

pages = {
  'lightek' => ['Lightek Media & Communications Group', 'The technology behind your next chapter.', 'Lightek develops connected software, digital media infrastructure, and independently deployable platforms for organizations and creators.', 'Explore our private-label partnership program and solutions built on one adaptable platform.', '/site/plp', 'Explore Lightek PLP'],
  'solutions' => ['Solutions Built for Real Operations', 'One connected technology ecosystem.', 'From CMS and digital publishing to community experiences, media delivery, and operational workflows, Lightek provides configurable capabilities without forcing each business into a separate codebase.', 'Choose the operating profile that matches your organization, then deploy it into an isolated customer environment.', '/site/plp', 'View Product Configurations'],
  'plp' => ['Lightek Private Label Partners', 'Your brand. Your infrastructure. Lightek technology.', 'Launch a branded digital business on the shared Lightek-site foundation. Each customer deployment is independently hosted and configured for its own products, audience, and workflows.', 'Business, Social, Media, Creator, and Enterprise profiles share one maintained software foundation. Availability and integrations vary by configuration.', '/site/plp-business', 'Start With Business'],
  'plp-business' => ['Lightek Business', 'Own your business presence.', 'A configurable website and business operations foundation for companies that want their own branded digital destination.', 'Configure your content, offerings, and customer experience using the Lightek platform. Deployment and commercial terms are established during onboarding.', '/site/plp', 'Explore PLP Program'],
  'plp-social' => ['Lightek Social', 'Make your community your own.', 'A branded community experience designed for independent hosting and future cross-instance network discovery.', 'Social federation is an engineering workstream, not a launched capability. Request the current deployment scope before purchasing.', '/site/plp', 'Explore PLP Program'],
  'plp-media' => ['Lightek Media', 'Build a destination for your content.', 'A configurable digital publishing and media experience for content businesses seeking greater brand control.', 'Streaming and device delivery depend on enabled services and completed integrations. Discuss your distribution requirements during onboarding.', '/site/plp', 'Explore PLP Program'],
  'plp-creator' => ['Lightek Creator', 'Create, publish, and grow under your brand.', 'A configurable creator platform that brings your publishing identity and audience experience into one independent digital property.', 'Creator tools and monetization workflows are configured according to the services available for your deployment.', '/site/plp', 'Explore PLP Program'],
  'plp-enterprise' => ['Lightek Enterprise', 'Your digital operations, connected.', 'A configurable platform foundation for organizations that require defined roles, policies, operational processes, and independent infrastructure.', 'Integrations, governance controls, service levels, and support are established through an enterprise implementation plan.', '/site/plp', 'Explore PLP Program'],
  'technology' => ['The Lightek Technology Ecosystem', 'One core. Configured for many businesses.', 'Dymond Site powers page content. Lightek-site integrates platform operations. Nevaeh analyzes knowledge and work requirements while Gatekeeper governs authorized execution.', 'Our platform design emphasizes reusable capabilities, separated customer deployments, and versioned operational workflows.', '/site/solutions', 'Explore Solutions'],
  'experience' => ['Engineering Experience', 'Built through real product engineering.', 'Our engineering background includes work on major streaming and digital media properties, including Paramount+, Disney+, and BET+. This describes professional experience, not an endorsement of Lightek by those companies.', 'Bring your product objectives and operational constraints to a technical partnership discussion.', '/site/plp', 'Explore Partnership Options']
}.freeze

puts "PHASE1C_PROFILE site_id=#{site.id} host=#{site.host} apply=#{apply}"
# Preflight every planned page and its original draft state before ANY writes.
plans = pages.map do |slug, content|
  page = site.pages.find_by(slug: slug)
  abort "BLOCKED: missing prepared commercial page #{slug}" unless page
  abort "BLOCKED: commercial page already published #{slug}" if page.published?
  sections_count = page.sections.count
  if sections_count.positive?
    puts "SKIP_EXISTING_CONTENT slug=#{slug} sections=#{sections_count}"
    next
  end
  title, heading, subheading, first_body, cta_url, cta_label = content
  blocks = [
    ['hero', {'eyebrow' => 'LIGHTEK MCG', 'heading' => heading, 'subheading' => subheading, 'cta_label' => cta_label, 'cta_url' => cta_url}],
    ['rich_text', {'body' => first_body}],
    ['cta_banner', {'heading' => title, 'subheading' => 'Learn more about the Lightek technology and partnership ecosystem.', 'cta_label' => cta_label, 'cta_url' => cta_url}]
  ]
  blocks.each do |kind, data|
    record = page.sections.build(kind: kind, data: data, position: 0)
    abort "BLOCKED: invalid section slug=#{slug} kind=#{kind} errors=#{record.errors.full_messages.inspect}" unless record.valid?
  end
  page.association(:sections).reset
  puts "#{apply ? 'PLAN_CREATE' : 'WOULD_CREATE'} slug=#{slug} sections=3"
  [page, blocks]
end.compact

if apply
  DymondSite::Section.transaction do
    plans.each do |page, blocks|
      locked = site.pages.lock.find(page.id)
      abort "BLOCKED: page changed during apply slug=#{page.slug}" if locked.published? || locked.sections.exists?
      blocks.each_with_index do |(kind, data), index|
        locked.sections.create!(kind: kind, data: data, position: index + 1)
      end
      puts "CREATED_SECTIONS slug=#{page.slug} count=3"
    end
  end
end
puts "PHASE1C_OK apply=#{apply} pages=#{plans.length} sections=#{plans.length * 3}"
