# frozen_string_literal: true

paths = Dir[
  Rails.root.join(
    "db",
    "seeds",
    "studio_generated",
    "*.rb"
  )
].sort

paths.each { |path| load path }

puts "Generated Studio capability files loaded: #{paths.length}"
