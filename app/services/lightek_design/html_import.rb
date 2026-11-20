# frozen_string_literal: true
require "base64"

module LightekDesign
  class HtmlImport
    def self.records_for(user:, site:)
      scope = DymondSite::SiteTemplate.where("key LIKE ?", "ld_html_import_%")
        .where("CAST(settings -> 'html_import' ->> 'site_id' AS TEXT) = ?", site.id.to_s)
      unless user.role.to_s == "super_admin"
        scope = scope.where("CAST(settings -> 'html_import' ->> 'owner_id' AS TEXT) = ?", user.id.to_s)
      end
      scope.order(created_at: :desc).limit(20)
    end

    def self.enqueue!(user:, site:, html_file:, css_file: nil, js_file: nil, name: nil, create_page: false, product_selector: nil, background: false)
      raise ArgumentError, "Workspace editor access is required." unless user&.role.to_s.in?(%w[admin super_admin client white_label])
      html = read_file!(html_file, %w[.html .htm])
      css = css_file.present? ? read_file!(css_file, %w[.css]) : ""
      javascript = read_file!(js_file, %w[.js]) if js_file.present?
      record = DymondSite::SiteTemplate.create!(key: "ld_html_import_#{SecureRandom.hex(10)}", name: name.to_s.strip.presence || html_file.original_filename.first(120),
        settings: {"html_import" => {"status" => "queued", "owner_id" => user.id, "site_id" => site.id,
          "html" => html, "css" => css, "filename" => html_file.original_filename, "name" => name.to_s.first(120),
          "javascript" => javascript, "js_filename" => js_file&.original_filename.to_s.first(120).presence,
          "create_page" => create_page, "product_selector" => product_selector.to_s.first(200)}})
      if background
        begin
          job = LightekDesign::HtmlImportJob.perform_later(record.id)
          raise ActiveJob::EnqueueError, "Import was not enqueued" unless job
        rescue StandardError
          record.update!(settings: record.settings.deep_merge("html_import" => {"status" => "failed", "error" => "The import queue is unavailable. Use Convert now to process the saved source."}))
        end
      else
        # Inputs are bounded to 500 KB each. Interactive imports must not depend
        # on a separately started worker; reuse the same idempotent job inline.
        LightekDesign::HtmlImportJob.perform_now(record.id)
        record.reload
      end
      record
    end

    def self.read_file!(file, extensions)
      unless file.respond_to?(:original_filename) && extensions.include?(File.extname(file.original_filename.to_s).downcase) &&
          file.size.between?(1, HtmlDocument::MAX_BYTES)
        raise ArgumentError, "Choose a #{extensions.join('/')} file up to 500 KB."
      end
      value = file.read(HtmlDocument::MAX_BYTES + 1).force_encoding(Encoding::UTF_8)
      raise ArgumentError, "Upload a UTF-8 #{extensions.join('/')} file up to 500 KB." unless value.valid_encoding? && value.bytesize <= HtmlDocument::MAX_BYTES && !value.include?("\0")
      value
    end

    def self.interactive_preview(meta)
      raise ActiveRecord::RecordNotFound if meta["javascript"].blank?

      document = Nokogiri::HTML5.parse(meta.fetch("html"))
      module_script = document.css('script[type="module"][src]').any? do |node|
        File.basename(node["src"].split(/[?#]/, 2).first.to_s) == meta["js_filename"]
      end
      document.css("script,iframe,frame,frameset,object,embed,link,meta,base").remove
      nonce = SecureRandom.base64(24)
      csp = Nokogiri::XML::Node.new("meta", document)
      csp["http-equiv"] = "Content-Security-Policy"
      csp["content"] = "default-src 'none'; script-src 'nonce-#{nonce}'; style-src 'unsafe-inline'; img-src https: data:; font-src https: data:; base-uri 'none'; form-action 'none'"
      document.at_css("head").prepend_child(csp)

      style = Nokogiri::XML::Node.new("style", document)
      style.content = HtmlDocument.clean_css(meta["css"])
      document.at_css("head").add_child(style)

      script = Nokogiri::XML::Node.new("script", document)
      script["nonce"] = nonce
      script["type"] = "module" if module_script
      script["src"] = "data:text/javascript;base64,#{Base64.strict_encode64(meta.fetch("javascript"))}"
      document.at_css("body").add_child(script)
      document.to_html
    end

    def self.process!(record)
      record.with_lock do
        meta = record.settings.fetch("html_import").deep_dup
        next record if meta["status"] == "complete"
        site = DymondSite::Site.find(meta.fetch("site_id"))
        user = User.find(meta.fetch("owner_id"))
        raise ActiveRecord::RecordNotFound unless LightekSettings::WebsiteIdentity.sites_for(user).exists?(id: site.id)
        document, warnings = HtmlDocument.convert(html: meta.fetch("html"), css: meta["css"], name: meta["name"], product_selector: meta["product_selector"].presence)
        workspace = StudioDocument.create!(user: user, name: document["name"])
        release = StudioDocument.publish!(record: workspace, document: document, expected_revision: StudioDocument.revision(workspace))
        page = WebsiteDesigns.import!(site: site, design: release.key) if meta["create_page"]
        if page && meta["product_selector"].present?
          candidates = site.manifest.to_h.fetch("lightek_commerce_design_pages", {}).merge(page.id.to_s => release.key)
          site.update!(manifest: site.manifest.to_h.merge("lightek_commerce_starter_page_id" => page.id, "lightek_commerce_design_key" => release.key, "lightek_commerce_design_pages" => candidates))
        end
        meta.merge!("status" => "complete", "document_id" => workspace.id, "release_key" => release.key, "page_id" => page&.id, "warnings" => warnings)
        record.update!(settings: record.settings.merge("html_import" => meta))
      end
      record
    end
  end
end
