# frozen_string_literal: true

require 'cgi'
require 'uri'

module NevaehOs
  module PublicRelations
    CATEGORY = 'Press Releases'
    module_function

    def releases(site)
      LightekBlog::Entry.publicly_visible.where(site: site, category: CATEGORY).includes(:post)
        .order(published_at: :desc, id: :desc)
    end

    def release!(site, actor, values)
      WebsiteMarketing.allowed!(values, %w[title summary facts press_email status])
      title = field!(values, 'title', 160)
      summary = field!(values, 'summary', 400)
      facts = field!(values, 'facts', 4000)
      contact = field!(values, 'press_email', 254)
      validate_email!(contact)
      status = values.fetch('status', 'draft')
      raise ArgumentError, 'Choose draft or published for the release.' unless %w[draft published].include?(status)

      paragraphs = [summary, *facts.split(/\n\s*\n/)].map { |paragraph| "<p>#{CGI.escapeHTML(paragraph)}</p>" }
      email = CGI.escapeHTML(contact)
      paragraphs << "<p><strong>Media contact</strong> <a href=\"mailto:#{email}\">#{email}</a></p>"
      WebsiteJournal.write!(site, actor, {
        'title' => title, 'excerpt' => summary, 'content' => paragraphs.join("\n"),
        'category' => CATEGORY, 'status' => status
      })
    end

    def pitch!(site, values)
      WebsiteMarketing.allowed!(values, %w[entry_id outlet angle recipient])
      entry_id = values.fetch('entry_id').to_s
      raise ArgumentError, 'Choose a published press release.' unless entry_id.match?(/\A[1-9][0-9]{0,17}\z/)

      release = releases(site).find(entry_id)
      outlet = field!(values, 'outlet', 120)
      angle = field!(values, 'angle', 800)
      recipient = field!(values, 'recipient', 254)
      validate_email!(recipient)
      origin = LightekGrowth::SearchDiscovery.origin(site)
      raise ArgumentError, 'Set a public hostname before pitching a release.' unless origin

      url = "#{origin}/blog/#{release.slug}"
      {
        'entry_id' => release.id, 'outlet' => outlet, 'recipient' => recipient,
        'subject' => "Story idea for #{outlet}: #{release.post.title}".squish.truncate(180),
        'body' => <<~TEXT.strip,
          Hello #{outlet} team,

          #{angle}

          #{release.excerpt}
          Press release: #{url}

          If this fits your coverage, please reply to discuss an interview or request more detail.

          #{site.name}
        TEXT
        'release_url' => url
      }
    end

    def validate_email!(value)
      raise ArgumentError, 'Enter a single email address.' unless URI::MailTo::EMAIL_REGEXP.match?(value) && !value.match?(/[?&#%]/)
    end

    def field!(values, key, limit)
      value = values.fetch(key)
      unless value.is_a?(String) && value.strip.length.between?(1, limit)
        raise ArgumentError, "Enter #{key.humanize.downcase} (up to #{limit} characters)."
      end
      value.strip
    end
  end
end
