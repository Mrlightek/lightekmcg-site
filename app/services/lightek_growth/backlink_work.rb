require 'csv'

module LightekGrowth
  class BacklinkWork
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @access = Workspace.new(actor: actor, site: site)
    end

    def record!(source:, target:, status:)
      @site.with_lock do
        @access.revalidate!
        source = normalize(source)
        target = normalize(target)
        record = Backlink.find_or_initialize_by(site: @site, fingerprint: Digest::SHA256.hexdigest([source, target].join("\n")))
        record.assign_attributes(source_url: source, target_url: target) if record.new_record?
        if record.persisted? && record.status != status
          record.assign_attributes(outreach_draft: nil, approved_at: nil, approved_by: nil)
        end
        record.update!(status: status, updated_by: @actor)
        record
      end
    end

    def import!(file)
      raise ArgumentError, 'Choose a CSV under 512 KB.' unless file.respond_to?(:read) && file.size <= 512.kilobytes

      csv = CSV.parse(file.read.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF"), headers: true)
      raise ArgumentError, 'Import at most 500 backlinks at a time.' unless csv.size.between?(1, 500)

      headers = csv.headers
      source_key = headers.include?('Source URL') ? 'Source URL' : 'Source page'
      target_key = headers.include?('Target URL') ? 'Target URL' : 'Target page'
      unless headers.include?(source_key) && headers.include?(target_key)
        raise ArgumentError, 'Use CSV columns Source URL and Target URL.'
      end

      @site.with_lock do
        @access.revalidate!
        csv.each do |row|
          source = normalize(row[source_key])
          target = normalize(row[target_key])
          fingerprint = Digest::SHA256.hexdigest([source, target].join("\n"))
          record = Backlink.find_or_initialize_by(site: @site, fingerprint: fingerprint)
          status = record.status.in?(%w[verified lost]) ? record.status : 'reported'
          record.assign_attributes(source_url: source, target_url: target) if record.new_record?
          record.assign_attributes(outreach_draft: nil, approved_at: nil, approved_by: nil) if record.status == 'prospect'
          record.update!(status: status, updated_by: @actor)
        end
      end
      csv.size
    rescue CSV::MalformedCSVError
      raise ArgumentError, 'Could not read the backlink CSV.'
    end

    def authorize_draft!(id:, version:)
      @site.with_lock do
        @access.revalidate!
        LightekAgency::PackagePolicy.authorize!(@site.tenant, 'nevaeh')
        backlink = Backlink.where(site: @site, status: 'prospect').find(id)
        return backlink if backlink.approved_at? && backlink.approved_by_id == @actor.id
        raise ArgumentError, 'This backlink changed. Review the current prospect before authorizing a new draft.' unless backlink.updated_at.iso8601(6) == version
        brief = Brief.find_by(site: @site)
        offer = brief&.offering.presence || @site.name
        draft = <<~TEXT
          Hi, I came across #{backlink.source_url} and thought your readers might find our page about #{offer} useful.

          Here's the page: #{backlink.target_url}

          If it adds something useful to your piece, would you consider including it as a resource? Happy to send more context.
        TEXT
        backlink.update!(outreach_draft: draft, approved_by: @actor, approved_at: Time.current, updated_by: @actor)
        backlink
      end
    end

    private

    def normalize(value)
      uri = Backlink.url(value) or raise ArgumentError, 'Enter a full HTTP or HTTPS URL without a fragment.'
      uri.normalize.to_s
    end
  end
end
