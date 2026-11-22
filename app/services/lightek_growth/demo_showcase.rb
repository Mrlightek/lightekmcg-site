# frozen_string_literal: true

module LightekGrowth
  module DemoShowcase
    DOCUMENTED_IMAGES = {
      'website' => { 'docs/marketing/screenshots/website-editor.png' => 'Design & Content workspace with sample data' },
      'studio' => {
        'docs/studio/screenshots/media-studio-editor.png' => 'Media studio editor',
        'docs/studio/screenshots/live-rooms-setup.png' => 'Live Studio room setup'
      },
      'sales' => { 'docs/marketing/screenshots/sales-pipeline.png' => 'Sales pipeline with sample deals' },
      'commerce' => { 'docs/marketing/screenshots/commerce-orders.png' => 'Commerce orders with sample customers' },
      'growth' => { 'docs/marketing/screenshots/marketing-copilot.png' => 'Marketing Copilot with a sample offer' },
      'nevaeh' => { 'docs/marketing/screenshots/nevaeh-guide.png' => 'Nevaeh guide for automating work' }
    }.freeze
    MAX_BYTES = 5.megabytes
    module_function

    def demo_booking?(site)
      setting = LightekAgency::Demos.public_setting(site.host)
      setting.public_site_id == site.id
    rescue ActiveRecord::RecordNotFound
      false
    end

    def promotion_ready?(showcase, link)
      showcase.approved_at && showcase.page.published? && link.enabled? &&
        link.destination_path == "/site/#{showcase.page.slug}" && walkthrough_section?(showcase) && demo_booking?(showcase.site)
    end

    def walkthrough_section?(showcase)
      showcase.page.sections.where(kind: 'lightek_feature_showcase').any? { |section| section.data['showcase_id'].to_s == showcase.id.to_s }
    end

    def add_documented_images!(clip)
      existing = clip.screenshots_blobs.map { |blob| blob.metadata['source'] }
      DOCUMENTED_IMAGES.fetch(clip.feature_key, {}).each do |source, caption|
        next if existing.include?(source) || clip.screenshots.count >= 4

        path = Rails.root.join(source)
        File.open(path, 'rb') do |io|
          clip.screenshots.attach(io: io, filename: path.basename.to_s, content_type: 'image/png', identify: false,
            metadata: { 'caption' => caption, 'source' => source })
        end
      end
    end

    def verify_screenshots!(showcase)
      missing = []
      showcase.clips.each do |clip|
        images = clip.screenshots_attachments.to_a
        missing << clip.title if images.empty?
        images.each { |image| image!(clip, image.id) }
      end
      if showcase.snapshot['demo_promotion_link_id'] && missing.any?
        raise ArgumentError, "Add a product screenshot for every feature shown. Missing: #{missing.join(', ')}."
      end
    rescue ActiveRecord::RecordNotFound
      raise ArgumentError, 'A walkthrough screenshot is unavailable. Restore or replace it before proceeding.'
    end

    def add_capture!(clip, upload, caption)
      raise ArgumentError, 'Enter a screenshot caption up to 120 characters.' unless caption.to_s.strip.length.between?(1, 120)
      unless upload.respond_to?(:tempfile) && upload.size.between?(1, MAX_BYTES)
        raise ArgumentError, 'Capture a PNG screenshot up to 5 MB.'
      end
      io = upload.tempfile
      raise ArgumentError, 'Choose a PNG screenshot.' unless Marcel::MimeType.for(io) == 'image/png'

      io.rewind
      header = io.read(24).to_s
      dimensions = header.byteslice(16, 8)&.unpack('NN')
      unless header.byteslice(12, 4) == 'IHDR' && dimensions&.size == 2 && dimensions.all? { |size| size.between?(1, 4096) }
        raise ArgumentError, 'Use a PNG with dimensions up to 4096 × 4096.'
      end
      io.rewind
      raise ArgumentError, 'Each feature can have up to four screenshots.' if clip.screenshots.count >= 4

      clip.screenshots.attach(io: io, filename: "#{clip.feature_key}-demo.png", content_type: 'image/png', identify: false,
        metadata: { 'caption' => caption.strip, 'source' => 'demo-window' })
    end

    def image!(clip, id)
      blob = clip.screenshots_attachments.find(id).blob
      unless blob.content_type == 'image/png' && blob.byte_size.between?(1, MAX_BYTES) && blob.service.exist?(blob.key)
        raise ActiveRecord::RecordNotFound
      end

      blob
    end

    def funnel(site, campaign_id)
      link_ids = Link.where(site: site, campaign_id: campaign_id).select(:id)
      visits = Visit.where(site: site, link_id: link_ids)
      outcomes(site, visits)
    end

    def outcomes(site, visits)
      requests = LightekAgency::DemoRequest.where(agency_id: site.tenant_id, growth_visit_id: visits.select(:id))
      demos = LightekAgency::Demo.where(agency_id: site.tenant_id, demo_request_id: requests.select(:id))
      paid = LightekCommerce::Order.where(id: demos.select(:upgrade_order_id), status: %w[paid fulfilled]).where.not(paid_at: nil)
      { visits: visits.count, requests: requests.count, activated: requests.where(status: 'activated').count, paid: paid.count }
    end
  end
end
