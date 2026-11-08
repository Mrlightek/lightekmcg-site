# frozen_string_literal: true
module LightekDesign
  class TemplateBranding
    DEFAULT_CREDIT = "Template by LightekMCG"
    def initialize(site) = @site = site
    def settings = (@site.respond_to?(:manifest) ? @site.manifest.to_h : {}).fetch("template_branding", {}).to_h
    def white_label?
      tenant = @site.tenant if @site.respond_to?(:tenant)
      settings["white_label_enabled"] == true || tenant&.feature_entitlements&.active&.exists?(feature_slug: "white_label_agency") == true
    end
    def credit
      return DEFAULT_CREDIT unless white_label?
      settings["show_credit"] == false ? "" : settings["credit"].to_s.presence || DEFAULT_CREDIT
    end
    def self.save!(site:, actor:, values:)
      super_admin = actor&.role.to_s == "super_admin"
      policy = new(site)
      raise ArgumentError, "White-label agency access is required" unless super_admin || policy.white_label?
      text = values["credit"].to_s.strip
      raise ArgumentError, "Keep the credit under 120 characters" if text.length > 120
      site.with_lock do
        manifest = site.manifest.to_h.deep_dup
        branding = manifest.fetch("template_branding", {})
        branding["white_label_enabled"] = values["white_label_enabled"] == "1" if super_admin
        branding["credit"] = text
        branding["show_credit"] = values["show_credit"] == "1"
        manifest["template_branding"] = branding
        site.update!(manifest: manifest)
      end
    end
  end
end
