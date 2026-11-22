# frozen_string_literal: true

module LightekGrowth
  module DemoShowcase
    DOCUMENTED_STUDIO_IMAGES = %w[media-studio-editor live-rooms-setup].freeze
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
        link.destination_path == "/site/#{showcase.page.slug}" && demo_booking?(showcase.site)
    end

    def add_documented_images!(clip)
      return unless clip.feature_key == 'studio' && clip.screenshots.empty?

      DOCUMENTED_STUDIO_IMAGES.each do |name|
        path = Rails.root.join('docs', 'studio', 'screenshots', "#{name}.png")
        File.open(path, 'rb') do |io|
          clip.screenshots.attach(io: io, filename: "#{name}.png", content_type: 'image/png', identify: false,
            metadata: { 'caption' => name.tr('-', ' ').humanize, 'source' => "docs/studio/screenshots/#{name}.png" })
        end
      end
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
      requests = LightekAgency::DemoRequest.where(agency_id: site.tenant_id, growth_visit_id: visits.select(:id))
      demos = LightekAgency::Demo.where(agency_id: site.tenant_id, demo_request_id: requests.select(:id))
      paid = LightekCommerce::Order.where(id: demos.select(:upgrade_order_id), status: %w[paid fulfilled]).where.not(paid_at: nil)
      { visits: visits.count, requests: requests.count, activated: requests.where(status: 'activated').count, paid: paid.count }
    end
  end
end
