# frozen_string_literal: true
module LightekDesign
  class HtmlImportJob < ApplicationJob
    queue_as :default
    def perform(id)
      record = DymondSite::SiteTemplate.find_by(id: id)
      return unless record&.key.to_s.start_with?("ld_html_import_")
      HtmlImport.process!(record)
    rescue StandardError => error
      Rails.logger.error("Website HTML import #{id} failed: #{error.class}")
      record&.reload&.with_lock do
        next if record.settings.dig("html_import", "status") == "complete"
        meta = record.settings.fetch("html_import").merge("status" => "failed", "error" => error.is_a?(ArgumentError) ? error.message : "Import failed. Check the source files and retry.")
        record.update!(settings: record.settings.merge("html_import" => meta))
      end
    end
  end
end
