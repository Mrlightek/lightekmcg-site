# frozen_string_literal: true

module NevaehOs
  module WebsiteJournal
    ARTICLE_FIELDS = %w[title slug content excerpt category status].freeze
    module_function

    def inspect_entries(site, values)
      WebsiteMarketing.allowed!(values, %w[entry_id])
      entries = LightekBlog::Entry.where(site: site).includes(:post)
      if values['entry_id']
        entry = entries.find(values.fetch('entry_id'))
        receipt(entry).merge('content' => entry.post.content, 'excerpt' => entry.excerpt)
      else
        { 'entries' => entries.order(updated_at: :desc, id: :desc).limit(30).map { |entry| receipt(entry) } }
      end
    end

    def write!(site, actor, values)
      WebsiteMarketing.allowed!(values, ARTICLE_FIELDS + %w[entry_id revision brief])
      entry = LightekBlog::Entry.where(site: site).includes(:post).find(values.fetch('entry_id')) if values.key?('entry_id')
      attributes = values.slice(*ARTICLE_FIELDS)
      unless attributes.values.all? { |value| value.is_a?(String) }
        raise ArgumentError, 'Article fields must be text.'
      end
      if entry
        unless values.fetch('revision') == entry.lock_version
          raise ArgumentError, 'This article has changed. Inspect its current revision before editing.'
        end
        if attributes.key?('slug') && attributes['slug'] != entry.slug
          raise ArgumentError, 'Keep the existing URL when editing an article.'
        end
        attributes = { 'title' => entry.post.title, 'content' => entry.post.content, 'slug' => entry.slug,
          'excerpt' => entry.excerpt, 'category' => entry.category, 'status' => entry.status,
          'lock_version' => entry.lock_version }.merge(attributes)
      else
        title = attributes.fetch('title')
        attributes['slug'] = title.parameterize if attributes['slug'].blank?
        attributes['status'] ||= 'draft'
      end
      unless attributes.fetch('title').strip.length.between?(1, 160)
        raise ArgumentError, 'Enter an article title up to 160 characters.'
      end
      if values.key?('brief')
        raise ArgumentError, 'Supply either article content or a writing brief.' if values.key?('content')
        attributes['content'] = draft_body(actor, attributes.fetch('title'), values.fetch('brief'))
      end

      saved = LightekBlog::Editor.save!(site: site, user: actor, entry: entry, attributes: attributes)
      receipt(saved)
    rescue ActiveRecord::StaleObjectError
      raise ArgumentError, 'This article has changed. Inspect its current revision before editing.'
    end

    def draft_body(actor, title, brief)
      WebsiteMarketing.allowed!(brief, %w[facts call_to_action])
      facts = brief.fetch('facts')
      unless facts.is_a?(String) && facts.strip.present?
        raise ArgumentError, 'Give Nevaeh the facts to cover in the article.'
      end
      templates = ['Here’s what to know about {topic}.', '{facts}']
      templates << '{call_to_action}' if brief['call_to_action'].present?
      NevaehIntelligences::WritingEngine.generate(format: 'post', actor: actor,
        context: brief.merge('topic' => title), profile: { 'format' => 'post', 'templates' => templates }).fetch('text')
    end

    def receipt(entry)
      { 'entry_id' => entry.id, 'title' => entry.post.title, 'slug' => entry.slug, 'category' => entry.category,
        'article_status' => entry.status, 'published' => LightekBlog::Entry.publicly_visible.exists?(id: entry.id),
        'revision' => entry.lock_version, 'path' => "/blog/#{entry.slug}" }
    end
  end
end
