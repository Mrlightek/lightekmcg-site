# frozen_string_literal: true
# Rails runner: bin/rails runner script/commercial_cms_seed.rb
# Default: dry run. APPLY=1 is allowed only in development and requires SITE_HOST.
# Creates missing draft pages only. Never overwrites current pages/sections/nav.

module LightekCommercialCmsSeed
  PAGES = {
    'lightek' => ['Lightek MCG', 'The infrastructure behind digital independence.'],
    'solutions' => ['Lightek Enterprise Solutions', 'Your business. Your platform.'],
    'plp' => ['Lightek Private Label Partners', 'Your brand. Powered by Lightek.'],
    'plp-business' => ['Lightek PLP Business', 'Business operations on your own platform.'],
    'plp-social' => ['Lightek PLP Social', 'Your community. Your independent instance.'],
    'plp-media' => ['Lightek PLP Media', 'Your stories. Your network.'],
    'plp-creator' => ['Lightek PLP Creator', 'Your content. Your audience.'],
    'plp-enterprise' => ['Lightek PLP Enterprise', 'Configurable technology for your organization.'],
    'technology' => ['Lightek Technology', 'One platform, many capabilities.'],
    'experience' => ['Engineering Experience', 'Platform engineering and communications infrastructure experience.']
  }.freeze

  def self.run!
    abort 'BLOCKED: Rails environment is production.' if Rails.env.production? && ENV['APPLY'] == '1'
    host = ENV.fetch('SITE_HOST', '').strip.downcase
    abort 'BLOCKED: provide SITE_HOST (exact existing site host)' if host.empty?
    abort 'BLOCKED: invalid host format' unless host.match?(/\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/) && !host.include?('..')
    site = DymondSite::Site.find_by(host: host)
    abort "BLOCKED: no existing DymondSite::Site with host=#{host}" unless site

    apply = ENV['APPLY'] == '1'
    abort 'BLOCKED: APPLY only permitted in development.' if apply && !Rails.env.development?

    puts "COMMERCIAL_CMS_PROFILE site_id=#{site.id} host=#{site.host} environment=#{Rails.env} apply=#{apply}"
    puts 'NOTE: pages are intentionally drafts with no sections. Registry-backed sections require a separate verified step.'
    if apply
      DymondSite::Page.transaction do
        PAGES.each_with_index do |(slug, values), index|
          title, _headline = values
          existing = site.pages.find_by(slug: slug)
          if existing
            puts "PRESERVED slug=#{slug} id=#{existing.id}"
            next
          end
          page = site.pages.create!(slug: slug, title: title, published: false, position: 1000 + index)
          puts "CREATED_DRAFT slug=#{slug} id=#{page.id}"
        end
      end
    else
      PAGES.each do |slug, (title, headline)|
        existing = site.pages.find_by(slug: slug)
        puts "#{existing ? 'PRESERVE' : 'WOULD_CREATE_DRAFT'} slug=#{slug} title=#{title.inspect} headline=#{headline.inspect}"
      end
    end
    puts "CMS_SEED_OK apply=#{apply}"
  end
end

LightekCommercialCmsSeed.run!
