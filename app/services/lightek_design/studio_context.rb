# frozen_string_literal: true
module LightekDesign
  class StudioContext < ActiveSupport::CurrentAttributes
    attribute :released_designs, :requested_designs, :visible_designs
    def self.resolve(key)
      self.requested_designs ||= {}
      return requested_designs[key] if requested_designs.key?(key)
      raise KeyError, "Unknown design" unless key.to_s.match?(/\Ald_release_\d+_v\d+\z/)
      row = DymondSite::SiteTemplate.find_by(key: key)
      definition = row&.settings&.fetch("lightek_studio_release", nil)
      unless definition
        row = DymondSite::SiteTemplate.where("key LIKE ?", "lightek_site_%_#{key}").first
        definition = row&.settings&.fetch("lightek_studio_snapshot", nil)
      end
      raise KeyError, "Unknown design" unless definition.is_a?(Hash)
      requested_designs[key] = definition
    end
    def self.visible(user)
      return {} unless user
      self.visible_designs ||= {}
      cache_key = [user.id, user.role.to_s]
      visible_designs[cache_key] ||= begin
        rows = DymondSite::SiteTemplate.where("key LIKE ?", "ld_release_%")
        unless user.role.to_s == "super_admin"
          rows = rows.where("CAST(settings -> 'lightek_studio_release' ->> 'owner_id' AS TEXT) = ?", user.id.to_s)
        end
        rows.pluck(:key, :settings).to_h.transform_values { |settings| settings.fetch("lightek_studio_release") }
      end
    end
    def self.designs
      self.released_designs ||= if DymondSite::SiteTemplate.table_exists?
        DymondSite::SiteTemplate.where("key LIKE ? OR key LIKE ?", "ld_release_%", "lightek_site_%_ld_release_%").pluck(:key, :settings).each_with_object({}) do |(key, settings), result|
          definition = settings["lightek_studio_release"] || settings["lightek_studio_snapshot"]
          design_key = settings["lightek_studio_snapshot"] ? settings["lightek_design"] : key
          result[design_key] = definition if design_key && definition.is_a?(Hash)
        end
      else
        {}
      end
    end
  end
end
