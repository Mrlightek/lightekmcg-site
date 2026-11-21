# frozen_string_literal: true

module NevaehIntelligences
  # Controller routes are the inventory. Only reviewed code-map links count as
  # bindings, even when another action under the same controller is connected.
  class PlatformCoverage
    ENGINES = %w[DymondBank DymondBooking DymondCatalog DymondDash DymondKb DymondStudio].freeze

    def initialize(route_sets:, code_map:, unavailable_route_sets: [])
      @route_sets = route_sets
      @code_map = code_map
      @unavailable_route_sets = unavailable_route_sets
    end

    def self.installed(query: nil)
      route_sets = {'Host application' => Rails.application.routes}
      ENGINES.each do |name|
        engine = "#{name}::Engine".safe_constantize
        route_sets[name] = engine.routes if engine
      end
      new(route_sets: route_sets, code_map: CodeKnowledge.new.search,
        unavailable_route_sets: ENGINES - route_sets.keys).report(query: query)
    end

    def report(query: nil)
      index = @code_map.fetch('entries').each_with_object({}) do |entry, endpoints|
        entry.fetch('endpoints', []).each do |endpoint|
          key = endpoint.values_at('source', 'method', 'action')
          (endpoints[key] ||= []) << {
            'capability' => entry.dig('capability', 'key'),
            'binding_status' => entry.fetch('binding_status'),
            'coverage' => endpoint.fetch('coverage')
          }
        end
      end
      rows = @route_sets.flat_map do |source, route_set|
        route_set.routes.filter_map do |route|
          controller, action = route.defaults.values_at(:controller, :action)
          next unless controller && action

          target = "#{controller}##{action}"
          method = route.verb
          bindings = index.fetch([source, method, target], [])
          {'source'=>source, 'method'=>method, 'path'=>route.path.spec.to_s, 'action'=>target,
           'bindings'=>bindings, 'status'=>status(bindings)}
        end
      end.uniq.sort_by { |row| row.values_at('source', 'path', 'method', 'action') }
      terms = query.to_s.downcase.split.first(10)
      matches = rows.select do |row|
        text = row.values_at('source', 'method', 'path', 'action', 'status').join(' ').downcase
        terms.all? { |term| text.include?(term) }
      end
      counts = rows.map { |row| row.fetch('status') }.tally
      remaining = rows.size - counts.fetch('bound', 0)
      loaded_endpoints = rows.map { |row| row.values_at('source', 'method', 'action') }
      stale = (index.keys - loaded_endpoints).filter_map do |source, method, action|
        next unless @route_sets.key?(source)

        {'source'=>source, 'method'=>method, 'action'=>action, 'bindings'=>index.fetch([source, method, action])}
      end
      {'total_routes'=>rows.size, 'counts'=>counts, 'routes_without_full_binding'=>remaining,
       'all_loaded_routes_bound'=>rows.any? && remaining.zero?, 'stale_route_bindings'=>stale,
       'route_sets'=>@route_sets.keys, 'unavailable_route_sets'=>@unavailable_route_sets, 'routes'=>matches}
    end

    private

    def status(bindings)
      return 'unmapped' if bindings.empty?

      active = bindings.select { |binding| %w[enabled registers_on_dispatch].include?(binding.fetch('binding_status')) }
      return 'binding_unavailable' if active.empty?

      %w[bound partial handoff].find { |coverage| active.any? { |binding| binding.fetch('coverage') == coverage } }
    end
  end
end
