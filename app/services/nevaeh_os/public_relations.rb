# frozen_string_literal: true

require 'cgi'
require 'uri'

module NevaehOs
  module PublicRelations
    CATEGORY = 'Press Releases'
    KEY = 'nevaeh_public_relations'
    ROLE = 'public_relations'
    FEATURES = %w[website marketing nevaeh].freeze
    OPERATIONS = {
      'press_release' => ['Write press release', %w[title summary facts press_email status entry_id revision], 'entry_id'],
      'release_status' => ['Change press release publication', %w[entry_id revision status], 'article_status'],
      'media_pitch' => ['Draft media pitch', %w[entry_id outlet angle recipient], 'body'],
      'contact' => ['Save media contact', %w[email outlet contact_basis], 'contact_id'],
      'suppress' => ['Stop outreach to contact', %w[email], 'contact_id'],
      'send_pitch' => ['Queue media pitch', %w[pitch_id], 'message_id'],
      'follow_up' => ['Queue media follow-up', %w[pitch_id angle], 'message_id'],
      'coverage' => ['Log press coverage', %w[entry_id outlet url notes], 'url'],
      'monitor' => ['Check a media source', %w[url phrase], 'source_url'],
      'response_brief' => ['Prepare media response brief', %w[title facts response next_update], 'body'],
      'report' => ['Review PR activity', [], 'generated_at']
    }.freeze
    MAIL_KEY = /\Anevaeh_pr_([1-9]\d*)_([1-9]\d*)_([a-f0-9]{32})_(pitch|followup)\z/

    def self.capability(operation)
      raise ArgumentError, 'Choose a supported PR operation.' unless OPERATIONS.key?(operation)

      "press.#{operation}"
    end
    module_function

    def entries(site)
      LightekBlog::Entry.where(site: site, category: CATEGORY)
    end

    def releases(site)
      entries(site).publicly_visible.includes(:post)
        .order(published_at: :desc, id: :desc)
    end

    def grant_for(site, actor)
      grant = site.manifest.to_h[KEY]
      grant if grant && grant['actor_id'] == actor.id
    end

    def configure!(site:, actor:, enabled:, mailbox_id: nil)
      actor.reload
      site.with_lock do
        unless site.tenant == actor || actor.role == 'super_admin'
          raise ArgumentError, 'Only the website owner or platform operator can assign public relations.'
        end

        manifest = site.manifest.to_h.dup
        if enabled
          FEATURES.each { |feature| LightekAgency::PackagePolicy.authorize!(site.tenant, feature) }
          account = mailbox!(actor, mailbox_id) if mailbox_id.present?
          current = grant_for(site, actor)
          unless current && current['mailbox_id'] == account&.id
            manifest[KEY] = { 'actor_id' => actor.id, 'key' => SecureRandom.hex(16), 'mailbox_id' => account&.id }
          end
        else
          manifest.delete(KEY)
        end
        site.update!(manifest: manifest)
      end
    end

    def bind(actor, command)
      return command if command.key?('delegation_id')

      site = WebsiteMarketing.site_for(actor, id!(command, 'site_id'))
      command.merge('delegation_id' => grant_for(site, actor)&.fetch('key'))
    end

    def authorize!(actor, command)
      site = WebsiteMarketing.site_for(actor, id!(command, 'site_id'))
      grant = grant_for(site, actor)
      unless grant && grant.fetch('key') == command['delegation_id']
        raise ArgumentError, 'Assign the PR SME to this website before starting PR work.'
      end
      FEATURES.each { |feature| LightekAgency::PackagePolicy.authorize!(site.tenant, feature) }
      operation = command.fetch('operation')
      capability(operation)
      values = command.fetch('values')
      WebsiteMarketing.allowed!(values, OPERATIONS.fetch(operation)[1])
      raise ArgumentError, 'Use a bounded PR brief.' if values.to_json.bytesize > 12_000

      mailbox!(actor, grant['mailbox_id']) if %w[send_pitch follow_up].include?(operation)
      site
    end

    def perform!(actor:, command:, action_id:)
      site = authorize!(actor, command)
      operation = command.fetch('operation')
      values = command.fetch('values')
      previous = changes(site, actor).find_by(action_id: action_id)
      return previous.result.merge('change_id' => previous.id) if previous

      scan = monitor(values) if operation == 'monitor'
      site.with_lock do
        authorize!(actor, command)
        previous = changes(site, actor).find_by(action_id: action_id)
        return previous.result.merge('change_id' => previous.id) if previous

        result = case operation
        when 'press_release' then release!(site, actor, values)
        when 'release_status' then release_status!(site, actor, values)
        when 'media_pitch' then pitch!(site, values)
        when 'contact', 'suppress' then save_contact!(site, values, suppress: operation == 'suppress')
        when 'coverage' then coverage!(site, values)
        when 'monitor' then scan
        when 'response_brief' then response_brief(values)
        when 'report' then report(site, actor)
        when 'send_pitch', 'follow_up' then submit!(site, actor, values, followup: operation == 'follow_up')
        end
        receipt = changes(site, actor).create!(action_id: action_id, site_id: site.id, actor_id: actor.id,
          operation: operation, result: result.merge('site_id' => site.id, 'status' => 'completed', 'operation' => operation))
        receipt.result.merge('change_id' => receipt.id)
      end
    rescue KeyError => error
      raise ArgumentError, "Missing PR input: #{error.key}."
    end

    def changes(site, actor)
      LightekGrowth::WebsiteChange.where(site_id: site.id, actor_id: actor.id)
    end

    def contacts(site)
      LightekGrowth::PressContact.where(site_id: site.id)
    end

    def mailboxes(actor)
      LightekMail::Access.accounts(actor).where(user_id: actor.id)
    rescue LightekMail::Access::Denied
      LightekMail::Account.none
    end

    def mailbox!(actor, id)
      account = mailboxes(actor).find_by(id: id)
      raise ArgumentError, 'Choose an active Lightek mailbox you own for PR outreach.' unless account&.sending_ready?

      account
    end

    def save_contact!(site, values, suppress:)
      email = field!(values, 'email', 254).downcase
      validate_email!(email)
      contact = contacts(site).find_or_initialize_by(email: email)
      if suppress
        contact.outlet ||= email
        contact.contact_basis ||= 'Do not contact'
      else
        raise ArgumentError, 'This contact is on the do-not-contact list.' if contact.suppressed?

        contact.outlet = field!(values, 'outlet', 120)
        contact.contact_basis = field!(values, 'contact_basis', 240)
      end
      contact.update!(suppressed: suppress)
      { 'contact_id' => contact.id, 'outlet' => contact.outlet, 'suppressed' => contact.suppressed? }
    end

    def coverage!(site, values)
      release = releases(site).find(id!(values, 'entry_id'))
      url = field!(values, 'url', 2_048)
      address = URI.parse(url)
      unless %w[http https].include?(address.scheme) && address.host.present? && address.userinfo.nil?
        raise ArgumentError, 'Enter the public coverage URL.'
      end

      { 'entry_id' => release.id, 'url' => url, 'outlet' => field!(values, 'outlet', 120),
        'notes' => field!(values, 'notes', 800) }
    rescue URI::InvalidURIError
      raise ArgumentError, 'Enter the public coverage URL.'
    end

    def monitor(values)
      url = field!(values, 'url', 1200)
      raise ArgumentError, 'Choose a public HTTPS source page.' unless JournalEditorial.source_url?(url)

      phrase = field!(values, 'phrase', 120)
      document = WebDocument.fetch(url, follow_redirects: false)
      pattern = /(?<![[:alnum:]])#{Regexp.escape(phrase)}(?![[:alnum:]])/i
      text = "#{document.fetch(:title)}\n#{document.fetch(:body)}"
      match = text.match(pattern)
      excerpt = text[[match.begin(0) - 50, 0].max, 170].squish if match
      { 'source_url' => document.fetch(:url), 'source_title' => document.fetch(:title), 'checked_at' => Time.current.iso8601,
        'source_sha256' => document.fetch(:sha256), 'phrase' => phrase, 'matched' => match.present?, 'excerpt' => excerpt }
    end

    def response_brief(values)
      { 'title' => field!(values, 'title', 160), 'body' => [
        "Confirmed facts\n#{field!(values, 'facts', 4_000)}",
        "Proposed response\n#{field!(values, 'response', 2_000)}",
        "Next update\n#{field!(values, 'next_update', 200)}"
      ].join("\n\n") }
    end

    def report(site, actor)
      rows = changes(site, actor)
      grant = grant_for(site, actor)
      account = mailboxes(actor).find_by(id: grant&.fetch('mailbox_id'))
      pitches = rows.where(operation: 'media_pitch').order(id: :desc).limit(30)
      { 'generated_at' => Time.current.iso8601, 'published_releases' => releases(site).count,
        'active_contacts' => contacts(site).where(suppressed: false).count, 'coverage_items' => rows.where(operation: 'coverage').count,
        'recent_source_checks' => rows.where(operation: 'monitor').order(id: :desc).limit(10)
          .map { |row| row.result.slice('source_url', 'checked_at', 'phrase', 'matched') },
        'pitches' => pitches.map { |pitch| outreach_status(account, site, pitch) } }
    end

    def outreach_status(account, site, pitch)
      initial = outreach_message(account, site, pitch, 'pitch')
      followup = outreach_message(account, site, pitch, 'followup')
      replied = [initial, followup].compact.any? { |message| reply?(account, message) }
      { 'pitch_id' => pitch.id, 'outlet' => pitch.result.fetch('outlet'), 'delivery' => initial&.state || 'draft',
        'follow_up' => followup&.state, 'replied' => replied,
        'can_follow_up' => !!(followup.nil? && !replied && followup_due?(initial)) }
    end

    def outreach_message(account, site, pitch, step)
      return unless account

      account.messages.where("idempotency_key LIKE ? ESCAPE '!'", "nevaeh!_pr!_#{site.id}!_#{pitch.id}!_%!_#{step}")
        .order(:id).first
    end

    def followup_due?(message)
      message&.state == 'sent' && message.submitted_at && message.submitted_at <= 3.days.ago
    end

    def reply?(account, message)
      account.messages.where(direction: 'inbound', in_reply_to: [message.message_id, "<#{message.message_id}>"]).exists?
    end

    def submit!(site, actor, values, followup:)
      grant = grant_for(site, actor)
      account = mailbox!(actor, grant.fetch('mailbox_id'))
      pitch = changes(site, actor).where(operation: 'media_pitch').find(id!(values, 'pitch_id'))
      draft = pitch.result
      releases(site).find(draft.fetch('entry_id'))
      email = draft.fetch('recipient').downcase
      raise ArgumentError, 'Activate this media contact before sending.' unless contacts(site).exists?(email: email, suppressed: false)

      step = followup ? 'followup' : 'pitch'
      if (prior = outreach_message(account, site, pitch, step))
        return mail_receipt(prior, pitch)
      end

      attributes = { to: email, subject: draft.fetch('subject'), text: draft.fetch('body') }
      if followup
        initial = outreach_message(account, site, pitch, 'pitch')
        unless followup_due?(initial) && !reply?(account, initial)
          raise ArgumentError, 'Follow up three days after confirmed SMTP submission and only while there is no reply.'
        end
        attributes.merge!(subject: "Re: #{attributes.fetch(:subject)}", in_reply_to: "<#{initial.message_id}>",
          text: "#{field!(values, 'angle', 800)}\n\nPress release: #{draft.fetch('release_url')}\n\n#{site.name}")
      end
      key = "nevaeh_pr_#{site.id}_#{pitch.id}_#{grant.fetch('key')}_#{step}"
      message = LightekMail::Submission.create!(account: account, attributes: attributes, idempotency_key: key)
      mail_receipt(message, pitch)
    rescue LightekMail::Submission::Unavailable => error
      raise ArgumentError, error.message
    end

    def mail_receipt(message, pitch)
      { 'message_id' => message.id, 'delivery_state' => message.state, 'pitch_id' => pitch.id }
    end

    # Delivery can be delayed by the mail worker. Recheck the delegation, contact and release before SMTP.
    def delivery_allowed?(message, account)
      match = MAIL_KEY.match(message.idempotency_key.to_s)
      return true unless message.idempotency_key.to_s.start_with?('nevaeh_pr_')
      return false unless match

      site_id, pitch_id, token, step = match.captures
      actor = account.user
      site = WebsiteMarketing.site_for(actor, site_id)
      grant = grant_for(site, actor)
      return false unless grant && grant['key'] == token && grant['mailbox_id'] == account.id
      return false unless NevaehOsAgent.where(user: actor, system_key: ROLE, enabled: true, deleted_at: nil).exists?

      FEATURES.each { |feature| LightekAgency::PackagePolicy.authorize!(site.tenant, feature) }
      pitch = changes(site, actor).where(operation: 'media_pitch').find(pitch_id)
      draft = pitch.result
      return false unless releases(site).exists?(id: draft.fetch('entry_id')) &&
        contacts(site).exists?(email: draft.fetch('recipient').downcase, suppressed: false)
      return true if step == 'pitch'

      initial = outreach_message(account, site, pitch, 'pitch')
      initial&.state == 'sent' && !reply?(account, initial)
    rescue ActiveRecord::RecordNotFound, LightekAgency::PackagePolicy::Denied
      false
    end

    def id!(values, name)
      id = values.fetch(name).to_s
      raise ArgumentError, "Choose a valid #{name.humanize.downcase}." unless id.match?(/\A[1-9][0-9]{0,17}\z/)

      id
    end

    def release!(site, actor, values)
      WebsiteMarketing.allowed!(values, %w[title summary facts press_email status entry_id revision])
      title = field!(values, 'title', 160)
      summary = field!(values, 'summary', 400)
      facts = field!(values, 'facts', 4000)
      contact = field!(values, 'press_email', 254)
      validate_email!(contact)
      status = values.fetch('status', 'draft')
      raise ArgumentError, 'Choose draft, published or archived for the release.' unless %w[draft published archived].include?(status)

      paragraphs = [summary, *facts.split(/\n\s*\n/)].map { |paragraph| "<p>#{CGI.escapeHTML(paragraph)}</p>" }
      email = CGI.escapeHTML(contact)
      paragraphs << "<p><strong>Media contact</strong> <a href=\"mailto:#{email}\">#{email}</a></p>"
      revision = values.key?('entry_id') ? release_revision(site, values) : {}
      WebsiteJournal.write!(site, actor, {
        'title' => title, 'excerpt' => summary, 'content' => paragraphs.join("\n"),
        'category' => CATEGORY, 'status' => status
      }.merge(revision))
    end

    def release_revision(site, values)
      entry = entries(site).find(id!(values, 'entry_id'))
      { 'entry_id' => entry.id, 'revision' => Integer(values.fetch('revision').to_s, 10) }
    end

    def release_status!(site, actor, values)
      status = values.fetch('status')
      raise ArgumentError, 'Choose published or archived for the release.' unless %w[published archived].include?(status)

      WebsiteJournal.write!(site, actor, release_revision(site, values).merge('status' => status))
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
