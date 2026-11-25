# frozen_string_literal: true

require "digest"
require "json"

module LightekAgency
  class WebsiteReleases
    class Invalid < StandardError; end

    KEY = "lightek_agency_release"
    COMMERCE_KEYS = %w[lightek_commerce_starter_page_id lightek_commerce_design_key lightek_commerce_design_pages].freeze

    def initialize(site:, editor:, actor: editor.email_address)
      @site, @editor, @actor = site, editor, actor
      @target = [site.host, site.tenant_type, site.tenant_id]
    end

    def list
      lock_target do
        DymondSite::SiteTemplate.where(id: theme_ids).order(id: :desc).limit(20).filter_map do |template|
          receipt = template.settings[KEY]
          summarize(template, receipt) if receipt && receipt["site_id"] == @site.id
        end
      end
    end

    def stage!(upload:, name:, request_key:)
      raise Invalid, "Reload the release form before uploading." unless request_key.to_s.match?(/\A[a-f0-9-]{36}\z/)
      inputs = LightekDesign::ThemePackage.read!(upload)
      inputs_digest = Digest::SHA256.hexdigest(JSON.generate([
        name.to_s.strip, [*inputs.fetch(:files), inputs[:css_file]].compact.map do |file|
          [file.original_filename, Digest::SHA256.hexdigest(file.string)]
        end
      ]))
      lock_target do
        template = LightekDesign::SiteTheme.install!(site: @site, user: @editor, name: name, request_key: "agency-#{request_key}", **inputs)
        template.lock!
        receipt = template.settings[KEY]
        if receipt
          raise Invalid, "This request already staged a different theme." unless receipt["inputs_digest"] == inputs_digest
          return summarize(template, receipt)
        end

        pages = release_pages(template)
        raise Invalid, "This theme already contains published pages. Upload a separate release." if pages.any?(&:published?)

        receipt = {"site_id" => @site.id, "status" => "draft", "baseline" => live_binding, "inputs_digest" => inputs_digest,
          "revision" => fingerprint(template, pages), "staged_by" => @actor, "staged_at" => Time.current.iso8601}
        save!(template, receipt)
        summarize(template, receipt)
      end
    end

    def review!(id:, revision:)
      lock_target do
        template, receipt = release!(id)
        same_revision!(receipt, revision)
        raise Invalid, "Choose a draft release." unless receipt["status"] == "draft"
        raise Invalid, "The live theme changed. Prepare a new release." unless live_binding == receipt["baseline"]

        pages = release_pages(template)
        raise Invalid, "Review only unpublished release pages." if pages.any?(&:published?)

        receipt = receipt.merge("revision" => fingerprint(template, pages), "reviewed_by" => @actor, "reviewed_at" => Time.current.iso8601)
        save!(template, receipt)
        summarize(template, receipt)
      end
    end

    def deploy!(id:, revision:)
      lock_target do
        template, receipt = release!(id)
        same_revision!(receipt, revision)
        return summarize(template, receipt) if receipt["status"] == "deployed" && @site.active_template_id == template.id

        raise Invalid, "Choose a draft release." unless receipt["status"] == "draft"
        raise Invalid, "The live theme changed. Prepare and review a new release." unless live_binding == receipt["baseline"]
        pages = release_pages(template)
        raise Invalid, "Draft content changed after review. Prepare a new release." unless fingerprint(template, pages) == revision

        previous_nav_ids = @site.nav_menu&.nav_items&.pluck(:id) || []
        LightekDesign::SiteTheme.activate!(site: @site, user: @editor, template_id: template.id)
        pages.each { |page| page.update!(published: true) }
        receipt = receipt.merge("status" => "deployed", "active_binding" => live_binding,
          "deployed_revision" => fingerprint(template, pages), "deployed_by" => @actor, "deployed_at" => Time.current.iso8601,
          "added_menu_items" => @site.nav_menu.nav_items.where.not(id: previous_nav_ids).where(page_id: pages.map(&:id)).map { |item| menu_identity(item) })
        save!(template, receipt)
        summarize(template, receipt)
      end
    end

    def rollback!(id:, revision:)
      lock_target do
        template, receipt = release!(id)
        same_revision!(receipt, revision)
        return summarize(template, receipt) if receipt["status"] == "rolled_back"

        unless receipt["status"] == "deployed" && live_binding == receipt["active_binding"]
          raise Invalid, "This release is no longer the active theme."
        end
        pages = release_pages(template)
        unless fingerprint(template, pages) == receipt["deployed_revision"]
          raise Invalid, "Published content was edited after deployment. Review those edits before restoring."
        end

        baseline = receipt.fetch("baseline")
        previous_id = baseline["active_template_id"]
        if previous_id && !DymondSite::SiteTemplate.exists?(previous_id)
          raise Invalid, "The previous theme is unavailable."
        end
        @site.update!(active_template_id: previous_id,
          manifest: @site.manifest.to_h.except(*COMMERCE_KEYS).merge(baseline.fetch("commerce")))
        pages.each { |page| page.update!(published: false) }
        Array(receipt["added_menu_items"]).each do |original|
          item = @site.nav_menu&.nav_items&.lock&.find_by(id: original["id"])
          item.destroy! if item && menu_identity(item) == original && !item.children?
        end
        receipt = receipt.merge("status" => "rolled_back", "rolled_back_by" => @actor, "rolled_back_at" => Time.current.iso8601)
        save!(template, receipt)
        summarize(template, receipt)
      end
    end

    private

    def lock_target
      @site.with_lock do
        raise Invalid, "The client website ownership or hostname changed." unless @target == [@site.host, @site.tenant_type, @site.tenant_id]

        yield
      end
    end

    def theme_ids
      @site.manifest.to_h.fetch("lightek_site_themes", {}).filter_map { |key, id| id if key.start_with?("agency-") }
    end

    def live_binding
      {"target" => @target, "active_template_id" => @site.active_template_id, "commerce" => @site.manifest.to_h.slice(*COMMERCE_KEYS)}
    end

    def release!(id)
      template = DymondSite::SiteTemplate.where(id: theme_ids).lock.find(id)
      receipt = template.settings[KEY]
      raise ActiveRecord::RecordNotFound unless receipt && receipt["site_id"] == @site.id

      [template, receipt]
    end

    def release_pages(template)
      entries = template.settings.fetch(LightekDesign::SiteTheme::KEY).fetch("pages")
      entries.map { |entry| @site.pages.lock.find(entry.fetch("page_id")) }
    end

    def fingerprint(template, pages)
      content = pages.map do |page|
        [page.attributes.slice("id", "title", "slug", "position", "published"),
          page.sections.lock.order(:position, :id).map { |section| section.attributes.slice("id", "kind", "position", "data") }]
      end
      Digest::SHA256.hexdigest(JSON.generate(canonical([template.settings.except(KEY), content])))
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |child| canonical(child) }
      when Array then value.map { |child| canonical(child) }
      else value
      end
    end

    def menu_identity(item)
      item.attributes.slice("id", "page_id", "parent_id", "label", "external_url", "position")
    end

    def same_revision!(receipt, revision)
      raise Invalid, "Reload and review this release before continuing." unless receipt["revision"] == revision
    end

    def save!(template, receipt)
      template.update!(settings: template.settings.merge(KEY => receipt))
    end

    def summarize(template, receipt)
      entries = template.settings.fetch(LightekDesign::SiteTheme::KEY).fetch("pages")
      pages = @site.pages.where(id: entries.pluck("page_id")).index_by(&:id)
      {
        "id" => template.id, "name" => template.name, "status" => receipt.fetch("status"),
        "revision" => receipt.fetch("revision"), "active" => @site.active_template_id == template.id,
        "pages" => entries.filter_map do |entry|
          page = pages[entry.fetch("page_id")]
          entry.slice("role", "warnings").merge("slug" => page.slug) if page
        end
      }
    end
  end
end
