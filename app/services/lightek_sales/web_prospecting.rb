# frozen_string_literal: true

require 'uri'

module LightekSales
  class WebProspecting
    SOURCES = {
      'facebook' => {label: 'Facebook', host: 'www.facebook.com', hosts: %w[facebook.com www.facebook.com m.facebook.com],
        search_path: '/search/posts/', search_parameter: 'q'},
      'linkedin' => {label: 'LinkedIn', host: 'www.linkedin.com', hosts: %w[linkedin.com www.linkedin.com],
        search_path: '/search/results/content/', search_parameter: 'keywords'},
      'reddit' => {label: 'Reddit', host: 'www.reddit.com', hosts: %w[reddit.com www.reddit.com old.reddit.com],
        search_path: '/search/', search_parameter: 'q'}
    }.freeze

    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end

    def save!(provider:, post_url:, profile_url:, name:)
      @workspace.revalidate!
      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
      source = SOURCES.fetch(provider) { raise ArgumentError, 'Choose a prospecting source.' }
      profile = canonical_url(profile_url, source, provider, :profile)
      post = canonical_url(post_url, source, provider, :post)

      SocialProspect.create_or_find_by!(site: @site, provider: provider, web_profile_url: profile) do |prospect|
        prospect.assign_attributes(saved_by: @actor, web_source_url: post, web_display_name: name.to_s.strip.presence)
      end
    end

    private

    def canonical_url(value, source, provider, kind)
      error = "Paste a valid #{source.fetch(:label)} #{kind} link."
      value = value.to_s.strip
      raise ArgumentError, error unless value.bytesize.between?(1, 1024)

      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTPS) && source.fetch(:hosts).include?(uri.host&.downcase) && uri.port == 443 && uri.userinfo.nil?
        raise ArgumentError, error
      end
      if uri.path.split('/').any? { |segment| unsafe_segment?(segment) }
        raise ArgumentError, error
      end

      path = kind == :profile ? profile_path(uri, provider) : post_path(uri, provider)
      raise ArgumentError, error unless path

      "https://#{source.fetch(:host)}#{path}"
    rescue URI::InvalidURIError
      raise ArgumentError, error
    end

    def profile_path(uri, provider)
      path = uri.path.delete_suffix('/')
      case provider
      when 'facebook'
        if path == '/profile.php'
          id = query(uri)['id']
          return "/profile.php?id=#{id}" if id&.match?(/\A[0-9]+\z/)
        end
        person = path.match(%r{\A/people/[^/]+/([0-9]+)\z}i)
        return "/profile.php?id=#{person[1]}" if person
        return path.downcase if path.match?(%r{\A/[a-z0-9][a-z0-9.]+\z}i) &&
          !%w[/profile.php /permalink.php /story.php /login.php /login /home.php /search /groups /pages /watch /share /messages /reel /photo /photo.php /index.php /settings].include?(path.downcase)
      when 'linkedin'
        return path.downcase if path.match?(%r{\A/(?:in|company)/[a-z0-9_%.-]+\z}i)
      when 'reddit'
        match = path.match(%r{\A/(?:u|user)/([a-z0-9_-]+)\z}i)
        return "/user/#{match[1].downcase}" if match
      end
      nil
    end

    def post_path(uri, provider)
      path = uri.path.delete_suffix('/')
      case provider
      when 'facebook'
        if %w[/permalink.php /story.php].include?(path)
          id, post = query(uri).values_at('id', 'story_fbid')
          return "#{path}?story_fbid=#{post}&id=#{id}" if id&.match?(/\A[0-9]+\z/) && post&.match?(/\A[a-z0-9]+\z/i)
        end
        return path if path.match?(%r{\A/(?:[a-z0-9.]+/posts/[a-z0-9]+|groups/[a-z0-9._-]+/(?:posts|permalink)/[a-z0-9]+|share/[prv]/[a-z0-9]+|reel/[0-9]+)\z}i)
      when 'linkedin'
        return path if path.match?(%r{\A/(?:posts/[a-z0-9_%.-]+|feed/update/urn:li:(?:activity|share|ugcPost):[0-9]+)\z}i)
      when 'reddit'
        match = path.match(%r{\A/r/([a-z0-9_]+)/comments/([a-z0-9]+)(?:/[a-z0-9_%.-]+)?\z}i)
        return "/r/#{match[1].downcase}/comments/#{match[2].downcase}/" if match
        return path if path.match?(%r{\A/r/[a-z0-9_]+/s/[a-z0-9]+\z}i)
      end
      nil
    end

    def unsafe_segment?(segment)
      decoded = URI::DEFAULT_PARSER.unescape(segment)
      %w[. ..].include?(decoded) || decoded.match?(/[\/\\[:cntrl:]]/)
    end

    def query(uri)
      URI.decode_www_form(uri.query.to_s).to_h
    rescue ArgumentError
      {}
    end
  end
end
