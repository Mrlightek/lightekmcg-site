# frozen_string_literal: true
module Studio
  module Broadcasting
    class Application < ApplicationRecord
      self.table_name = "studio_broadcast_applications"
      PLATFORMS = %w[roku fire_tv apple_tv android_tv web].freeze
      DEFAULT_SETTINGS = {"accent"=>"#D4AF37", "background"=>"#080808", "autoplay"=>false,
        "captions"=>true, "search"=>true, "live"=>true, "catalog"=>true, "configuration_ttl"=>60,
        "catalog_source"=>"all", "channel_source"=>"all", "post_ids"=>[], "channel_ids"=>[],
        "welcome_message"=>"Culture. Community. Creators. Television."}.freeze
      belongs_to :site, class_name: "DymondSite::Site"
      validates :name, presence: true, length: {maximum: 120}
      validates :slug, format: {with: /\A[a-z0-9][a-z0-9_-]{0,63}\z/}, uniqueness: {scope: :site_id}
      validates :platform, inclusion: {in: PLATFORMS}
      validates :status, inclusion: {in: %w[draft published maintenance]}
      validates :minimum_client_version, format: {with: /\A\d+\.\d+\.\d+\z/}
      validate :settings_contract
      def configuration = DEFAULT_SETTINGS.merge(settings.to_h)
      private
      def settings_contract
        unless settings.is_a?(Hash) && (settings.keys - DEFAULT_SETTINGS.keys).empty?
          errors.add(:settings, "contains unsupported controls")
          return
        end
        config = configuration
        %w[accent background].each { |key| errors.add(:settings, "#{key} must be a hex color") unless config[key].to_s.match?(/\A#[0-9a-fA-F]{6}\z/) }
        %w[autoplay captions search live catalog].each { |key| errors.add(:settings, "#{key} must be on or off") unless [true,false].include?(config[key]) }
        errors.add(:settings, "refresh must be between 15 and 3600 seconds") unless config["configuration_ttl"].is_a?(Integer) && config["configuration_ttl"].between?(15,3600)
        %w[catalog_source channel_source].each { |key| errors.add(:settings, "#{key} must use all or selected records") unless %w[all selected].include?(config[key]) }
        {"post_ids"=>Post.where(site_id: site_id, distribution: %w[lightek_streaming octavia], kind: %w[video live]),
         "channel_ids"=>Channel.where(site_id: site_id)}.each do |key, scope|
          ids = config[key]
          unless ids.is_a?(Array) && ids.length <= 100 && ids.all? { |id| id.is_a?(Integer) } && ids.uniq.length == ids.length && scope.where(id: ids).count == ids.length
            errors.add(:settings, "#{key} must contain up to 100 unique records from this application")
          end
        end
        errors.add(:settings, "welcome message is too long") if config["welcome_message"].to_s.length > 300
      end
    end
  end
end
