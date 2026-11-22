# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'uri'

module NevaehOs
  module JournalEditorial
    CADENCES = { 'daily' => 1.day, 'weekly' => 1.week }.freeze
    module_function

    def configure!(site:, actor:, attributes:)
      command = WebsiteMarketing.bind(actor, command_for(site, 'journal_research', {}))
      WebsiteMarketing.authorize!(actor, command)
      topics = attributes.fetch('topics', '').lines.map(&:strip).reject(&:blank?).uniq
      sources = attributes.fetch('sources', '').lines.map(&:strip).reject(&:blank?).uniq
      raise ArgumentError, 'Enter 1–12 editorial topics, one per line.' unless topics.size.between?(1, 12) && topics.all? { |topic| topic.size.between?(3, 80) && topic.match?(/[[:alnum:]]/) }
      raise ArgumentError, 'Enter 1–5 public HTTPS source pages, one URL per line.' unless sources.size.between?(1, 5) && sources.all? { |url| source_url?(url) }
      cadence = attributes.fetch('cadence')
      status = attributes.fetch('article_status')
      raise ArgumentError, 'Choose daily or weekly and draft or published.' unless CADENCES.key?(cadence) && %w[draft published].include?(status)

      schedule = LightekBlog::EditorialSchedule.create_or_find_by!(site: site) do |row|
        row.assign_attributes(actor: actor, delegation_id: command.fetch('delegation_id'), revision: SecureRandom.uuid,
          cadence: cadence, article_status: status, topics: topics, sources: sources)
      end
      schedule.with_lock do
        WebsiteMarketing.authorize!(actor, command)
        schedule.update!(actor: actor, delegation_id: command.fetch('delegation_id'), revision: SecureRandom.uuid,
          cadence: cadence, topics: topics, sources: sources, article_status: status, enabled: true,
          social_draft: status == 'published' && attributes['social_draft'] == '1', next_run_at: Time.current,
          last_goal: nil, last_error: nil)
      end
      schedule
    rescue KeyError
      raise ArgumentError, 'Choose a cadence and publication mode.'
    end

    def pause!(site:, actor:)
      schedule = LightekBlog::EditorialSchedule.find_by!(site: site, actor: actor)
      schedule.with_lock { schedule.update!(enabled: false, next_run_at: nil, revision: SecureRandom.uuid) }
    end

    def dispatch!(schedule, now: Time.current)
      schedule.with_lock do
        return unless schedule.enabled? && schedule.next_run_at && schedule.next_run_at <= now
        return if schedule.last_goal&.status == 'running'

        actor = schedule.actor
        begin
          WebsiteMarketing.authorize!(actor, command_for(schedule.site, 'journal_research', {}).merge('delegation_id' => schedule.delegation_id))
          goal = Goals.create!(actor: actor, values: goal_values(schedule), request_key: "journal-#{schedule.id}-#{schedule.revision}-#{schedule.next_run_at.to_i}")
          Goals.control!(goal: goal, actor: actor, operation: 'start') if goal.status == 'draft'
          schedule.update!(last_goal: goal, next_run_at: now + CADENCES.fetch(schedule.cadence), last_error: nil)
        rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ArgumentError, LightekAgency::PackagePolicy::Denied => error
          schedule.update!(enabled: false, next_run_at: nil, last_error: error.message.first(500))
        end
      end
    end

    def goal_values(schedule)
      site = schedule.site
      stamp = { 'revision' => schedule.revision }
      steps = [
        { 'key' => 'research', 'label' => 'Read approved sources and select a topic', 'agent' => 'marketing_strategy',
          'command' => command_for(site, 'journal_research', stamp),
          'expectations' => [{ 'path' => 'result.story.source_url', 'present' => true }] },
        { 'key' => 'article', 'label' => 'Write and save the Journal article', 'agent' => 'marketing_strategy',
          'command' => command_for(site, 'journal_editorial_write', stamp.merge('story' => { '$step' => 'research', 'path' => 'result.story' })),
          'expectations' => [{ 'path' => 'result.article_status', 'equals' => schedule.article_status },
            { 'path' => 'result.published', 'equals' => schedule.article_status == 'published' }] }
      ]
      if schedule.social_draft?
        steps << { 'key' => 'promote', 'label' => 'Prepare the social campaign', 'agent' => 'marketing_strategy',
          'command' => command_for(site, 'journal_social_draft', stamp.merge('entry_id' => { '$step' => 'article', 'path' => 'result.entry_id' })),
          'expectations' => [{ 'path' => 'result.campaign_id', 'present' => true }] }
      end
      { 'title' => "Journal editorial cycle · #{site.name.to_s.first(105)}", 'steps' => steps }
    end

    def command_for(site, operation, values)
      { 'kind' => 'website_marketing', 'operation' => operation, 'site_id' => site.id, 'values' => values }
    end

    def active_schedule!(site, actor, command)
      schedule = LightekBlog::EditorialSchedule.find_by(site: site, actor: actor, enabled: true)
      unless schedule && schedule.revision == command.fetch('values')['revision'] && schedule.delegation_id == command['delegation_id']
        raise ArgumentError, 'This editorial schedule was paused, changed, or lost its website delegation.'
      end
      schedule
    end

    def research!(site, actor, command)
      schedule = active_schedule!(site, actor, command)
      candidates = schedule.sources.flat_map do |url|
        begin
          document = WebDocument.fetch(url, follow_redirects: false)
          stories(document, schedule.topics)
        rescue ArgumentError
          []
        end
      end
      rows = LightekBlog::Entry.where(site: site)
      story = candidates.sort_by { |item| [item.fetch('priority'), item.fetch('slug')] }.find do |item|
        !rows.where('slug LIKE ?', "%-#{item.fetch('fingerprint')}").exists?
      end
      raise ArgumentError, 'The approved sources had no readable, new material matching the editorial topics.' unless story

      { 'story' => story.except('priority') }
    end

    def stories(document, topics)
      title = document.fetch(:title).squish
      lines = document.fetch(:body).lines.first(300).map(&:squish).select { |line| line.length >= 65 && !line.start_with?('#') }
      topics.each_with_index.flat_map do |topic, priority|
        phrase = /(?<![[:alnum:]])#{Regexp.escape(topic)}(?![[:alnum:]])/i
        lines.grep(phrase).first(4).filter_map do |line|
          # A short attributed excerpt grounds the article without copying the source page.
          match_at = line[0...line.index(phrase)].split.length
          excerpt = line.split.drop([match_at - 5, 0].max).first(20).join(' ').truncate(155)
          next unless excerpt.length >= 55

          heading = "#{topic}: #{title}".truncate(155)
          fingerprint = Digest::SHA256.hexdigest(excerpt.downcase)[0, 16]
          { 'topic' => topic, 'title' => heading, 'slug' => "#{heading.parameterize.first(130).delete_suffix('-')}-#{fingerprint}",
            'fingerprint' => fingerprint, 'excerpt' => excerpt, 'source_url' => document.fetch(:url),
            'source_title' => title.first(200), 'source_sha256' => document.fetch(:sha256), 'priority' => priority }
        end
      end
    end

    def write!(site, actor, command)
      schedule = active_schedule!(site, actor, command)
      schedule.with_lock do
        active_schedule!(site, actor, command)
        story = command.fetch('values').fetch('story')
        raise ArgumentError, 'The researched source and topic must still be approved.' unless story.is_a?(Hash) && schedule.sources.include?(story['source_url']) && schedule.topics.include?(story['topic'])
        if LightekBlog::Entry.where(site: site).where('slug LIKE ?', "%-#{story.fetch('fingerprint')}").exists?
          raise ArgumentError, 'This source update already has a Journal article.'
        end

        article = WebsiteJournal.write!(site, actor, {
          'title' => story.fetch('title'), 'slug' => story.fetch('slug'), 'excerpt' => "A source update on #{story.fetch('topic')}.",
          'content' => article_body(story), 'category' => story.fetch('topic'), 'status' => schedule.article_status
        })
        article.merge('source_url' => story.fetch('source_url'), 'source_sha256' => story.fetch('source_sha256'))
      end
    end

    def social_draft!(site, actor, command)
      schedule = active_schedule!(site, actor, command)
      schedule.with_lock do
        active_schedule!(site, actor, command)
        raise ArgumentError, 'Social drafts are disabled for this schedule.' unless schedule.social_draft?
        entry = LightekBlog::Entry.publicly_visible.where(site: site).includes(:post).find(command.fetch('values').fetch('entry_id'))
        origin = LightekGrowth::SearchDiscovery.origin(site)
        raise ArgumentError, 'Set a public hostname before preparing a social campaign.' unless origin

        campaign = LightekMarketing::Campaign.create!(site: site, channel: 'social', status: 'draft',
          name: "Journal · #{entry.post.title}".truncate(160), headline: entry.post.title,
          message: entry.excerpt, cta_label: 'Read the Journal', cta_url: "#{origin}/blog/#{entry.slug}", content_review_required: true)
        variant = LightekMarketing::ContentVariant.create!(campaign.attributes.slice(*LightekMarketing::ContentVariant::COPY_FIELDS).merge(
          site: site, campaign: campaign, created_by: actor, status: 'draft', angle: 'journal', batch_key: "journal-#{entry.id}",
          baseline_digest: campaign.content_digest, source_snapshot: { 'journal_entry_id' => entry.id, 'journal_revision' => entry.lock_version }))
        { 'campaign_id' => campaign.id, 'variant_id' => variant.id, 'entry_id' => entry.id, 'campaign_status' => campaign.status, 'url' => campaign.cta_url }
      end
    end

    def article_body(story)
      escaped = story.slice('topic', 'source_title', 'source_url', 'excerpt').transform_values { |value| CGI.escapeHTML(value) }
      "<p>We’re following #{escaped.fetch('topic')} for our readers. Here's an update from #{escaped.fetch('source_title')}.</p>" \
        "<blockquote>#{escaped.fetch('excerpt')}</blockquote>" \
        "<p><a href=\"#{escaped.fetch('source_url')}\">Read the source for context and details</a>.</p>"
    end

    def source_url?(value)
      uri = URI.parse(value)
      value.bytesize <= 1200 && uri.is_a?(URI::HTTPS) && uri.port == 443 && !uri.userinfo && !uri.fragment &&
        LightekGrowth::SearchDiscovery::HOST_PATTERN.match?(uri.host.to_s)
    rescue URI::InvalidURIError
      false
    end
  end
end
