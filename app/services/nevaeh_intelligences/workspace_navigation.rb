# frozen_string_literal: true
module NevaehIntelligences
  module WorkspaceNavigation
    module_function
    def normalize(raw)
      raise ArgumentError, "Use up to 60 sidebar entries" unless raw.is_a?(Array) && raw.length <= 60
      seen = []
      raw.map do |row|
        raise ArgumentError, "Invalid sidebar entry" unless row.is_a?(Hash)
        row = row.stringify_keys.slice("id", "label", "path", "group", "hidden")
        id = row["id"].to_s
        raise ArgumentError, "Sidebar IDs must be unique" unless id.match?(/\A[a-z][a-z0-9_-]{0,60}\z/) && !seen.include?(id)
        seen << id
        raise ArgumentError, "Label and group are required (60 characters maximum)" unless %w[label group].all? { |key| row[key].is_a?(String) && row[key].strip.length.between?(1, 60) }
        # Relative paths only: no javascript URLs, remote origins, backslashes or query payloads.
        raise ArgumentError, "Choose an application path such as /dashboard/live" unless row["path"].is_a?(String) && row["path"].match?(%r{\A/[a-zA-Z0-9][a-zA-Z0-9/_.-]{0,250}(?:\#[a-zA-Z0-9/_-]*)?\z}) && row["path"].split("/").none? { |part| %w[. ..].include?(part) }
        row.merge("hidden" => [true, "1", "true"].include?(row["hidden"]))
      end
    end

    def entries(user:, defaults:, saved: nil)
      saved ||= NevaehWorkspacePreference.find_by(user: user)&.navigation || []
      available = defaults.index_by { |entry| entry.fetch("id") }
      rows = saved.filter_map do |entry|
        # System destinations retain their permission-filtered path and icon.
        base = available.delete(entry["id"])
        next unless base || entry["id"].start_with?("custom-")
        base ? base.merge(entry.slice("label", "group", "hidden")) : entry.merge("icon" => "ti-apps")
      end
      rows + available.values
    end
  end
end
