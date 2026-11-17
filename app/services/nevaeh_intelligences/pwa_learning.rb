require 'digest'
module NevaehIntelligences
  module PwaLearning
    PATHS = %w[docs/nevaeh/tutorials/pwa_business_model.md docs/pwa_launch_audit_20261117.md].freeze
    module_function
    def documents(library = SoftwareLibrary.new)
      indexed = library.documents.index_by { |doc| doc[:path] }
      PATHS.map { |path| indexed.fetch(path) { raise ArgumentError, "PWA learning source missing: #{path}" } }
    end
    def fingerprint(docs)
      Digest::SHA256.hexdigest(CanonicalJson.dump(docs.map { |doc| doc.slice(:path, :sha256) }))
    end
    def prepare!(actor:, library: SoftwareLibrary.new)
      NevaehOs::Language.authorize!(actor)
      docs = documents(library)
      digest = fingerprint(docs)
      build = nil
      actor.with_lock do
        build = NevaehManualBuild.find_or_create_by!(creator: actor, name: "PWA business model · #{digest.first(20)}")
      end
      selected = Struct.new(:documents).new(docs)
      Manuals.build!(build, library: selected, draft_bindings: false)
      raise ArgumentError, build.error.presence || 'PWA learning preparation failed' unless build.reload.status == 'ready'
      build.with_lock do
        build.update!(coverage: build.coverage.merge('pwa_learning' => {'source_sha256'=>digest,
          'source_paths'=>PATHS, 'execution'=>'reference_only',
          'execution_gaps'=>%w[central_youtube_upload free_instance_allocation verified_instance_migration creator_subscriptions live_gifts_and_tips funded_creator_payouts]}))
      end
      synced = sync_knowledge!(docs: docs, fingerprint: digest)
      build.with_lock do
        learning = build.coverage.fetch('pwa_learning').merge('knowledge_base' => synced ? 'synchronized' : 'engine_unavailable_software_library_available')
        build.update!(coverage: build.coverage.merge('pwa_learning' => learning))
      end
      build
    end
    def train!(build:, model:, actor:, epochs:)
      NevaehOs::Language.authorize!(actor)
      raise ArgumentError, 'Choose your own prepared PWA source build' unless build.creator_id == actor.id && build.status == 'ready'
      docs = documents
      expected = fingerprint(docs)
      raise ArgumentError, 'The PWA sources changed; prepare and review a fresh build' unless build.coverage.dig('pwa_learning', 'source_sha256') == expected && build.manifest.map { |row| row['path'] } == PATHS
      raise ArgumentError, 'Choose an enabled internal model' unless model.enabled? && model.visibility == 'internal'
      plan = nil
      actor.with_lock do
        plan = NevaehLearningPlan.where(actor: actor, language_model: model, nevaeh_manual_build: build).order(id: :desc).first
        if plan
          raise ArgumentError, 'Review the blocked learning plan and resume it from Digital Factory' if plan.status == 'blocked'
          return plan
        end
        Manuals.approve!(build: build, actor: actor)
        plan = LearningPlans.request!(build: build, model: model, actor: actor, epochs: epochs)
      end
      # The existing recovery scheduler advances this plan and queues bounded
      # native training. No checkpoint or neural text is activated here.
      plan
    end
    def sync_knowledge!(docs:, fingerprint:)
      return false unless defined?(DymondKb::Topic) && defined?(DymondKb::Article) && DymondKb::Topic.table_exists? && DymondKb::Article.table_exists?
      DymondKb::Article.transaction do
        topic = DymondKb::Topic.find_or_initialize_by(topic_id: 'lightek-pwa-business')
        topic.assign_attributes(name: 'Lightek PWA business model', icon: 'book-open', description: 'Source-backed PWA policy, current implementation and launch gaps.', sort_order: 25)
        topic.save!
        docs.each_with_index do |doc, index|
          article = DymondKb::Article.find_or_initialize_by(article_id: "lightek-pwa-source-#{index + 1}")
          article.assign_attributes(topic_id: topic.id, title: doc[:title], article_type: 'reference',
            excerpt: 'PWA membership, hosting, YouTube earnings, mail and verified completion boundaries.',
            body: doc[:body], read_minutes: [1, doc[:body].split.length / 180].max, featured: false, sort_order: index,
            metadata: {'source_path'=>doc[:path], 'source_sha256'=>doc[:sha256], 'pwa_learning_fingerprint'=>fingerprint,
              'kind'=>'pwa_business_reference', 'execution_authority'=>false})
          article.save!
        end
      end
      true
    end
  end
end
