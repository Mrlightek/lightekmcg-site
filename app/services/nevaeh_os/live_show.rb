# frozen_string_literal: true

module NevaehOs
  module LiveShow
    CAPABILITY = 'studio.live.prepare'
    ROLE = 'live_broadcast_producer'
    DESTINATIONS = { 'test' => 'Private test', 'lightek' => 'Lightek', 'restream' => 'Restream',
      'simulcast' => 'Lightek + Restream', 'tiktok' => 'TikTok' }.freeze
    module_function

    def authorize!(actor, command)
      ::Gatekeeper::StudioLivePolicy.authorize!(user: actor)
      site = LightekPwa::Policy.sites_for(actor).find(command.fetch('site_id'))
      values = command.fetch('values')
      unless values.is_a?(Hash) && (values.keys - %w[title brief scene_id destination]).empty?
        raise ArgumentError, 'Use a title, show brief, destination and optional scene.'
      end
      field!(values, 'title', 120)
      field!(values, 'brief', 2400)
      destination = values.fetch('destination', 'test')
      raise ArgumentError, 'Choose a supported broadcast destination.' unless DESTINATIONS.key?(destination)

      LightekPwa::Policy.new(user: actor, site: site).authorize!('watch') if %w[lightek simulcast].include?(destination)
      site
    rescue KeyError => error
      raise ArgumentError, "Missing live show input: #{error.key}."
    rescue ::Gatekeeper::StudioLivePolicy::Denied => error
      raise ArgumentError, error.message
    end

    def prepare!(actor, command, action_id)
      site = authorize!(actor, command)
      values = command.fetch('values')
      title = field!(values, 'title', 120)
      points = field!(values, 'brief', 2400).lines.map(&:strip).reject(&:blank?)
      raise ArgumentError, 'Enter up to 10 talking points, one per line.' if points.length > 10

      destination = values.fetch('destination', 'test')
      setup = setup_for(actor, site, values['scene_id']) if values['scene_id'].present?
      { 'status' => 'completed', 'site_id' => site.id, 'title' => title, 'destination' => destination,
        'cues' => [{ 'label' => 'Open', 'text' => "Welcome viewers to #{title}. Introduce what you're covering today." }] +
          points.map { |point| { 'label' => 'Talking point', 'text' => point } } +
          [{ 'label' => 'Close', 'text' => 'Recap what you covered, tell viewers where to follow the next update, and sign off.' }],
        'scene_id' => setup&.fetch(:scene_id), 'scene_revision' => setup&.fetch(:lock_version),
        'host_path' => "/dashboard/live?site_id=#{site.id}&show_id=#{action_id}" }
    end

    def for_host!(actor, site, id)
      action = NevaehOsAction.where(user: actor, status: 'completed').find(id)
      package = action.result
      unless action.command['kind'] == 'live_show' && package['site_id'] == site.id
        raise ActiveRecord::RecordNotFound
      end
      package
    end

    def setup_for(actor, site, scene_id)
      setup = Studio::Live::ProductionPreset.new(user: actor, site: site).read(scene_id)
      raise ArgumentError, 'Save a live setup for that scene before preparing the show.' unless setup[:preset]

      setup
    end

    def field!(values, key, limit)
      value = values[key]
      raise ArgumentError, "Enter #{key.humanize.downcase} up to #{limit} characters." unless value.is_a?(String) && value.strip.length.between?(1, limit)

      value.strip
    end
  end
end
