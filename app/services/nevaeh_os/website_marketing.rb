# frozen_string_literal: true

module NevaehOs
  module WebsiteMarketing
    KEY = 'nevaeh_website_marketing'
    CAPABILITIES = {
      'inspect' => 'website.marketing.inspect',
      'compose' => 'website.marketing.compose',
      'publication' => 'website.marketing.publication',
      'appearance' => 'website.marketing.appearance',
      'restore' => 'website.marketing.restore',
      'journal_inspect' => 'website.marketing.journal_inspect',
      'journal_write' => 'website.marketing.journal_write',
      'journal_research' => 'website.marketing.journal_research',
      'journal_editorial_write' => 'website.marketing.journal_editorial_write',
      'journal_social_draft' => 'website.marketing.journal_social_draft',
      'press_release' => 'website.marketing.press_release',
      'media_pitch' => 'website.marketing.media_pitch'
    }.freeze

    module_function

    def site_for(actor, site_id)
      LightekSettings::WebsiteIdentity.sites_for(actor.reload).find(site_id)
    end

    def configure!(actor:, site_id:, enabled:)
      site = site_for(actor, site_id)
      site.with_lock do
        site_for(actor, site.id)
        unless site.tenant == actor || actor.role == 'super_admin'
          raise ArgumentError, 'Only the website owner or platform operator can change this assignment.'
        end
        manifest = site.manifest.to_h.dup
        current = manifest[KEY]
        if enabled
          %w[website design marketing nevaeh].each { |feature| LightekAgency::PackagePolicy.authorize!(site.tenant, feature) }
          specialist = Agents.resolve!('marketing_strategy', actor)
          specialist.with_lock do
            capabilities = specialist.allowed_capabilities | ['website.marketing.*']
            specialist.update!(allowed_capabilities: capabilities) if specialist.allowed_capabilities != capabilities
          end
          unless current && current['actor_id'] == actor.id
            manifest[KEY] = { 'key' => SecureRandom.hex(24), 'actor_id' => actor.id, 'granted_at' => Time.current.iso8601 }
          end
        else
          manifest.delete(KEY)
        end
        site.update!(manifest: manifest)
      end
    end

    def bind(actor, command)
      return command if command['delegation_id']

      site_id = command.fetch('site_id')
      raise ArgumentError, 'Assign website work to a specific site ID.' unless site_id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)
      site = site_for(actor, site_id)
      command.merge('delegation_id' => site.manifest.to_h.dig(KEY, 'key'))
    end

    def authorize!(actor, command)
      site = site_for(actor, command.fetch('site_id'))
      grant = site.manifest.to_h[KEY]
      unless grant && grant['actor_id'] == actor.id && grant['key'].present? && grant['key'] == command['delegation_id']
        raise ArgumentError, 'Enable Nevaeh website delegation for this website before assigning this goal.'
      end
      %w[website design marketing nevaeh].each { |feature| LightekAgency::PackagePolicy.authorize!(site.tenant, feature) }
      CAPABILITIES.fetch(command.fetch('operation')) { raise ArgumentError, 'Unknown website operation.' }
      values = command.fetch('values')
      raise ArgumentError, 'Use a bounded website input object.' unless values.is_a?(Hash) && values.to_json.bytesize <= 12_000
      site
    end

    def perform!(actor:, command:, action_id:)
      site = authorize!(actor, command)
      operation = command.fetch('operation')
      values = command.fetch('values')
      if operation == 'journal_research'
        return JournalEditorial.research!(site, actor, command).merge('site_id' => site.id, 'status' => 'completed', 'operation' => operation)
      end

      site.with_lock do
        authorize!(actor, command)
        receipts = LightekGrowth::WebsiteChange.where(site_id: site.id)
        previous = receipts.find_by(action_id: action_id)
        return previous.result.merge('change_id' => previous.id) if previous

        before = previous_page(site, values) if %w[compose publication restore].include?(operation) && values['page_id']
        before = { 'template_id' => site.active_template_id, 'settings' => site.active_template&.settings } if operation == 'appearance'

        # The site lock serializes delegated article creation and grant changes.
        result = case operation
        when 'inspect' then inspect_site(site, values)
        when 'journal_inspect' then WebsiteJournal.inspect_entries(site, values)
        when 'journal_write' then WebsiteJournal.write!(site, actor, values)
        when 'journal_editorial_write' then JournalEditorial.write!(site, actor, command)
        when 'journal_social_draft' then JournalEditorial.social_draft!(site, actor, command)
        when 'press_release' then PublicRelations.release!(site, actor, values)
        when 'media_pitch' then PublicRelations.pitch!(site, values)
        when 'compose' then compose(site, actor, values)
        when 'publication' then publication(site, values)
        when 'appearance' then appearance(site, actor, values)
        when 'restore' then restore_page(site, actor, values, receipts)
        end
        receipt = result.merge('site_id' => site.id, 'status' => 'completed', 'operation' => operation)
        if %w[inspect journal_inspect].include?(operation)
          receipt
        else
          change = receipts.create!(action_id: action_id, actor_id: actor.id, operation: operation, previous_source: before, result: receipt)
          receipt.merge('change_id' => change.id)
        end
      end
    rescue KeyError => error
      raise ArgumentError, "Missing or unsupported website input: #{error.key}."
    end

    def previous_page(site, values)
      page = site.pages.lock.find(values.fetch('page_id'))
      imports = site.manifest.to_h.fetch('lightek_design_imports', {})
      designs = imports.select { |_key, id| id.to_s == page.id.to_s }
      LightekGrowth::Audits::Source.snapshot(page).except('site_context').merge('designs' => designs)
    end

    def inspect_site(site, values)
      allowed!(values, %w[page_id])
      if values['page_id']
        page = site.pages.find(values.fetch('page_id'))
        page_receipt(page, site).merge('sections' => page.sections.order(:position, :id).limit(30).pluck(:id, :kind, :position, :data).map do |id, kind, position, data|
          { 'id' => id, 'kind' => kind, 'position' => position, 'data' => data }
        end)
      else
        { 'pages' => site.pages.order(:position, :id).limit(50).pluck(:id, :title, :slug, :published).map do |id, title, slug, published|
            { 'page_id' => id, 'title' => title, 'slug' => slug, 'published' => published }
          end, 'design' => LightekDesign::Catalog.design_for(site), 'appearance_revision' => appearance_revision(site) }
      end
    end

    def compose(site, actor, values)
      allowed!(values, %w[page_id revision title slug sections published search_title description])
      title = values.fetch('title')
      slug = values.fetch('slug')
      raise ArgumentError, 'Enter a title up to 120 characters.' unless title.is_a?(String) && title.strip.length.between?(1, 120)
      unless slug.is_a?(String) && slug.length <= 160 && slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        raise ArgumentError, 'Use a valid lowercase page slug.'
      end
      published = boolean!(values.fetch('published'))
      page = if values['page_id']
        row = site.pages.lock.find(values.fetch('page_id'))
        check_revision!(row, values.fetch('revision'))
        raise ArgumentError, 'Keep the existing page slug when replacing its content.' unless slug == row.slug
        row
      else
        raise ArgumentError, 'That slug is in use. Inspect the existing page before editing.' if site.pages.exists?(slug: slug)
        site.pages.build(slug: slug, position: site.pages.maximum(:position).to_i + 1)
      end
      normalized = page_document(title, values.fetch('sections'))
      studio = LightekDesign::StudioDocument
      workspace = studio.create!(user: actor, name: title)
      release = studio.publish!(record: workspace, document: normalized, expected_revision: studio.revision(workspace))
      page.update!(title: title.strip, published: published)
      page.sections.destroy_all
      release.settings.fetch('lightek_studio_release').fetch('sections').each_with_index do |section, position|
        page.sections.create!(kind: section.fetch('kind'), position: position, data: section.fetch('data'))
      end
      imports = site.manifest.to_h.fetch('lightek_design_imports', {}).reject { |_key, id| id.to_s == page.id.to_s }
      site.update!(manifest: site.manifest.to_h.merge('lightek_design_imports' => imports.merge(release.key => page.id)))
      if values.key?('search_title') || values.key?('description')
        metadata = LightekGrowth::PageMetadata.find_or_initialize_by(site_id: site.id, page_id: page.id)
        metadata.assign_attributes(values.slice('search_title', 'description').transform_keys { |key| key == 'search_title' ? 'title_tag' : key })
        metadata.update!(updated_by: actor)
      end
      page_receipt(page.reload, site).merge('design_release' => release.key)
    end

    def page_document(title, sections)
      raise ArgumentError, 'Provide at least one native content block.' unless sections.is_a?(Array) && sections.length.between?(1, 30)

      studio = LightekDesign::StudioDocument
      normalized_sections = sections.map do |input|
        raise ArgumentError, 'Choose a native content block.' unless input.is_a?(Hash)
        allowed!(input, %w[block anchor data style])
        key = input.fetch('block')
        if %w[html starter].include?(key) || !LightekDesign::StudioBlocks.definitions.key?(key)
          raise ArgumentError, 'Choose a registered native content block.'
        end
        block = studio.new_block(key)
        data = input.fetch('data')
        raise ArgumentError, 'Supply the content fields for the block.' unless data.is_a?(Hash)
        if key == 'hero' && data['heading'].to_s.strip.blank?
          raise ArgumentError, 'Give the hero a heading.'
        end
        block.merge(input.slice('style')).merge('data' => data, 'anchor' => input.fetch('anchor', ''))
      end
      studio.normalize({ 'name' => title, 'base_design' => 'plain', 'sections' => normalized_sections })
    end

    def publication(site, values)
      allowed!(values, %w[page_id revision published])
      page = site.pages.lock.find(values.fetch('page_id'))
      check_revision!(page, values.fetch('revision'))
      desired = boolean!(values.fetch('published'))
      raise ArgumentError, 'Add content before publishing this page.' if desired && !page.sections.exists?

      page.update!(published: desired)
      page_receipt(page.reload, site)
    end

    def appearance(site, actor, values)
      allowed!(values, %w[revision design theme_id fonts colors])
      raise ArgumentError, 'Website appearance changed. Inspect it again.' unless values.fetch('revision') == appearance_revision(site)
      raise ArgumentError, 'Choose one design or theme.' if values['design'] && values['theme_id']
      if values['theme_id']
        LightekDesign::SiteTheme.activate!(site: site, user: actor, template_id: values.fetch('theme_id'))
      elsif values['design']
        key = values.fetch('design')
        LightekDesign::Catalog.selectable_designs(user: actor, active: LightekDesign::Catalog.design_for(site)).fetch(key) { raise ArgumentError, 'Choose an available design.' }
        LightekDesign::WebsiteDesigns.apply!(site: site, design: key)
      end
      fonts = values.fetch('fonts', {})
      colors = values.fetch('colors', {})
      allowed!(fonts, LightekDesign::WebsiteDesigns::FONT_KEYS)
      allowed!(colors, LightekDesign::StudioDocument::COLOR_KEYS)
      LightekDesign::WebsiteDesigns.save_fonts!(site: site, values: fonts) if fonts.any?
      if colors.any?
        template = site.reload.active_template
        raise ArgumentError, 'Apply a site-owned design before editing its palette.' unless template&.settings.to_h['lightek_site_id'].to_i == site.id
        palette = colors.transform_values { |color| LightekDesign::StudioDocument.color(color) }
        settings = template.settings
        template.update!(settings: settings.merge('tokens' => settings.fetch('tokens', {}).merge(palette)))
      end
      { 'design' => LightekDesign::Catalog.design_for(site.reload), 'active_template_id' => site.active_template_id,
        'appearance_revision' => appearance_revision(site) }
    end

    def restore_page(site, actor, values, receipts)
      allowed!(values, %w[page_id revision change_id])
      page = site.pages.lock.find(values.fetch('page_id'))
      check_revision!(page, values.fetch('revision'))
      change = receipts.find(values.fetch('change_id'))
      unless change.result['page_id'] == page.id && change.result['revision'] == values.fetch('revision') && change.previous_source
        raise ArgumentError, 'Only the latest matching page change with a saved prior version can be restored.'
      end

      source = change.previous_source
      page.update!(source.fetch('page').slice('title', 'published'))
      page.sections.destroy_all
      source.fetch('sections').each { |section| page.sections.create!(section.slice('kind', 'position', 'data')) }
      imports = site.manifest.to_h.fetch('lightek_design_imports', {}).reject { |_key, id| id.to_s == page.id.to_s }
      site.update!(manifest: site.manifest.to_h.merge('lightek_design_imports' => imports.merge(source.fetch('designs'))))
      metadata = LightekGrowth::PageMetadata.find_or_initialize_by(site_id: site.id, page_id: page.id)
      prior_metadata = source.fetch('metadata')
      if prior_metadata['exists']
        metadata.update!(prior_metadata.slice('title_tag', 'description').merge('updated_by' => actor))
      elsif metadata.persisted?
        metadata.destroy!
      end
      page_receipt(page.reload, site)
    end

    def boolean!(value)
      raise ArgumentError, 'Choose true or false for published.' unless value == true || value == false

      value
    end

    def allowed!(values, keys)
      raise ArgumentError, 'Unexpected website input fields.' unless values.is_a?(Hash) && (values.keys - keys).empty?
    end

    def check_revision!(page, revision)
      raise ArgumentError, 'Page changed. Inspect its current revision before editing.' unless page_revision(page) == revision
    end

    def page_revision(page)
      LightekGrowth::Audits::Source.digest(LightekGrowth::Audits::Source.snapshot(page).except('site_context'))
    end

    def appearance_revision(site)
      LightekGrowth::Audits::Source.digest([site.active_template_id, site.active_template&.settings.to_h])
    end

    def page_receipt(page, site)
      { 'page_id' => page.id, 'title' => page.title, 'slug' => page.slug, 'published' => page.published?,
        'revision' => page_revision(page), 'url' => LightekGrowth::SearchDiscovery.canonical_page(site, page.slug) }
    end
  end
end
