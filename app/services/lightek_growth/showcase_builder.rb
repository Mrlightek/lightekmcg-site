module LightekGrowth
  class ShowcaseBuilder
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @workspace = Workspace.new(actor: actor, site: site)
    end
    def authorize!
      @workspace.revalidate!
      raise ArgumentError, 'Website editing permission is required to build or approve this feature page' unless LightekSettings::WebsiteIdentity.sites_for(@actor).exists?(id: @site.id)
      %w[website studio].each { |feature| LightekAgency::PackagePolicy.authorize!(@site.tenant, feature) }
    end
    def start!(kit_id:, slug: 'features')
      @site.with_lock do
        authorize!
        kit = MarketingKit.where(site: @site).find(kit_id)
        raise ArgumentError, 'Prepare a current marketing kit before building its page' unless MarketingCopilot.new(actor: @actor, site: @site).current?(kit)
        if (previous = FeatureShowcase.find_by(marketing_kit: kit))
          raise ArgumentError, 'This kit already owns a showcase at another requested slug' unless previous.snapshot['requested_slug'] == slug
          return previous
        end
        cards = FeatureCatalog.rows(@site)
        raise ArgumentError, 'No reviewed platform feature cards are available for this website' if cards.empty?
        # The normal CMS executor refuses duplicate slugs and creates a draft.
        actual_slug = @site.pages.exists?(slug: slug) ? "#{slug}-#{kit.id}" : slug
        output = NevaehOs::WebsitePages.create!(actor: @actor, command: {'site_id'=>@site.id, 'values'=>{'title'=>"#{@site.name} features".first(160), 'slug'=>actual_slug}})
        page = @site.pages.find(output.fetch('page_id'))
        promotion = demo_promotion_link(kit, actual_slug)
        showcase = FeatureShowcase.create!(site: @site, marketing_kit: kit, page: page, created_by: @actor, token: SecureRandom.hex(24),
          snapshot: {'source'=>FeatureCatalog.snapshot, 'brief_revision'=>kit.snapshot['brief_revision'], 'cards'=>cards, 'requested_slug'=>slug, 'video_kind'=>'captioned_feature_overview', 'demo_promotion_link_id'=>promotion&.id})
        cards.each_with_index { |card,index| showcase.clips.create!(position: index, feature_key: card['key'], category: card['category'], title: card['title'], body: card['body']) }
        heading = promotion ? "See #{@site.name} in action" : "Explore #{@site.name}"
        intro = promotion ? 'See the product screens and choose what you want to try in your demo.' :
          'See the tools, understand what they do, and choose your next step.'
        page.sections.create!(kind: 'lightek_feature_showcase', position: 0,
          data: { 'showcase_id' => showcase.id.to_s, 'heading' => heading, 'intro' => intro })
        FeatureShowcaseJob.perform_later(showcase.id)
        showcase
      end
    end
    def render!(showcase)
      authorize!
      showcase = FeatureShowcase.where(site: @site).find(showcase.id)
      raise ArgumentError, 'The marketing kit changed or expired while rendering was queued; prepare a fresh kit' unless MarketingCopilot.new(actor: @actor, site: @site).current?(showcase.marketing_kit)
      raise ArgumentError, 'The source feature manual changed; review a fresh kit' unless showcase.snapshot['source']==FeatureCatalog.snapshot
      showcase.clips.each do |clip|
        authorize!
        DemoShowcase.add_documented_images!(clip)
        next if clip.ready?
        raise ArgumentError, 'A previously saved clip is unavailable; reconcile its storage before retrying' if clip.checksum.present?
        Studio::MediaProcess.temporary_directory('feature-overview-') do |directory|
          path = FeatureVideo.render!(title: clip.title, body: clip.body, directory: directory)
          File.open(path, 'rb') { |io| clip.file.attach(io: io, filename: "#{clip.feature_key}-overview.mp4", content_type: 'video/mp4', identify: false) }
          clip.update!(checksum: clip.file.blob.checksum)
          raise ArgumentError, 'Feature video did not persist' unless clip.reload.ready?
        end
      end
      raise ArgumentError, 'The feature page or clips failed read-back' unless showcase.page.sections.exists?(kind: 'lightek_feature_showcase') && showcase.clips.all?(&:ready?)
      showcase.clips.find_each { |clip| queue_studio_clip!(clip) }
      showcase.update!(status: 'completed', error: nil)
    end
    def approve!(id:)
      @site.with_lock do
        authorize!
        showcase = FeatureShowcase.where(site: @site).find(id)
        showcase.with_lock do
          raise ArgumentError, 'Wait for every saved video and review the current source' unless showcase.status=='completed' && showcase.clips.all?(&:ready?) && showcase.snapshot['source']==FeatureCatalog.snapshot
          screenshots = showcase.clips.flat_map { |clip| clip.screenshots_attachments.map { |image| DemoShowcase.image!(clip, image.id) } }
          if showcase.snapshot['demo_promotion_link_id'] && screenshots.empty?
            raise ArgumentError, 'Add a real product screenshot before approving the demo walkthrough.'
          end
          showcase.update!(approved_by: @actor, approved_at: Time.current)
        end
        showcase
      end
    end
    def receipt(showcase)
      authorize!
      showcase = FeatureShowcase.where(site: @site).find(showcase.id)
      raise ArgumentError, 'The saved feature videos are unavailable; reconcile storage before using this report' if showcase.status=='completed' && !showcase.clips.all?(&:ready?)
      {'site_id'=>@site.id, 'kit_id'=>showcase.marketing_kit_id, 'showcase_id'=>showcase.id, 'page_id'=>showcase.page_id,
        'status'=>showcase.status, 'success'=>showcase.status!='failed', 'error'=>showcase.error,
        'video_count'=>showcase.clips.count, 'screenshot_count'=>showcase.clips.sum { |clip| clip.screenshots.count },
        'demo_promotion_link_id'=>showcase.snapshot['demo_promotion_link_id'], 'page_published_at_creation'=>false,
        'text'=>"Feature showcase #{showcase.status}: native CMS draft plus captioned overview videos. Review the videos and page before publishing; these are not screen recordings.",
        'links'=>[{'label'=>'Review page and feature videos', 'url'=>Rails.application.routes.url_helpers.dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase.marketing_kit_id)}]}
    end

    private

    def demo_promotion_link(kit, slug)
      original = Link.where(site: @site, campaign: kit.campaign).find_by(id: kit.snapshot['link_id'])
      return unless original&.destination_path == '/request-demo'
      raise ArgumentError, 'Enable public demo requests for this website before building the walkthrough.' unless DemoShowcase.demo_booking?(@site)

      @workspace.create_link!(values: { campaign_id: kit.campaign_id, source: original.source,
        medium: original.medium, label: 'Demo walkthrough', destination_path: "/site/#{slug}" })
    end

    def queue_studio_clip!(clip)
      @actor.with_lock do
        asset=StudioAsset.find_or_initialize_by(owner:@actor,request_key:"growth-feature-clip-#{clip.id}")
        if asset.new_record?
          asset.assign_attributes(site:@site,name:clip.title.to_s.first(160),kind:"video",status:"uploaded")
          asset.file.attach(clip.file.blob)
          asset.save!
        end
        StudioAssetIngestJob.perform_later(asset.id) if asset.status=="uploaded"
      end
    end
  end
end
