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
        showcase = FeatureShowcase.create!(site: @site, marketing_kit: kit, page: page, created_by: @actor, token: SecureRandom.hex(24),
          snapshot: {'source'=>FeatureCatalog.snapshot, 'brief_revision'=>kit.snapshot['brief_revision'], 'cards'=>cards, 'requested_slug'=>slug, 'video_kind'=>'captioned_feature_overview'})
        cards.each_with_index { |card,index| showcase.clips.create!(position: index, feature_key: card['key'], category: card['category'], title: card['title'], body: card['body']) }
        page.sections.create!(kind: 'lightek_feature_showcase', position: 0, data: {'showcase_id'=>showcase.id.to_s, 'heading'=>"Explore #{@site.name}", 'intro'=>'See the tools, understand what they do, and choose your next step.'})
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
      showcase.update!(status: 'completed', error: nil)
    end
    def approve!(id:)
      @site.with_lock do
        authorize!
        showcase = FeatureShowcase.where(site: @site).find(id)
        raise ArgumentError, 'Wait for every saved video and review the current source' unless showcase.status=='completed' && showcase.clips.all?(&:ready?) && showcase.snapshot['source']==FeatureCatalog.snapshot
        showcase.update!(approved_by: @actor, approved_at: Time.current)
        showcase
      end
    end
    def receipt(showcase)
      authorize!
      showcase = FeatureShowcase.where(site: @site).find(showcase.id)
      raise ArgumentError, 'The saved feature videos are unavailable; reconcile storage before using this report' if showcase.status=='completed' && !showcase.clips.all?(&:ready?)
      {'site_id'=>@site.id, 'kit_id'=>showcase.marketing_kit_id, 'showcase_id'=>showcase.id, 'page_id'=>showcase.page_id,
        'status'=>showcase.status, 'success'=>showcase.status!='failed', 'error'=>showcase.error,
        'video_count'=>showcase.clips.count, 'page_published_at_creation'=>false,
        'text'=>"Feature showcase #{showcase.status}: native CMS draft plus captioned overview videos. Review the videos and page before publishing; these are not screen recordings.",
        'links'=>[{'label'=>'Review page and feature videos', 'url'=>Rails.application.routes.url_helpers.dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase.marketing_kit_id)}]}
    end
  end
end
