# frozen_string_literal: true
module LightekCommunity
  # Audience is an additional boundary; membership, ownership, moderation and
  # post visibility cannot weaken it. Gender is private, self-declared profile data.
  module Audience
    VALUES = %w[everyone women men].freeze
    GENDERS = %w[unspecified woman man].freeze
    module_function
    def for_profile(profile)
      { "woman" => "women", "man" => "men" }[profile&.community_gender]
    end
    def visible(scope, profile:, super_admin: false)
      return scope if super_admin
      scope.where(audience: ["everyone", for_profile(profile)].compact)
    end
    def authorize!(value, profile:, super_admin: false)
      raise ArgumentError, "Unsupported audience" unless VALUES.include?(value)
      return if super_admin || value == "everyone" || value == for_profile(profile)
      raise AccessDenied, "This space is restricted to its selected audience"
    end
    def compatible!(community, value)
      return unless community && community.audience != "everyone"
      raise ArgumentError, "A post cannot select a different audience from its community" unless value == "everyone" || value == community.audience
    end
  end
end
