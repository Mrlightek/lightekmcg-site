#!/bin/bash
set -e
cd ~/Desktop/Development/lightek_kernel

echo "Fixing engine.rb.tt template (Engine.helpers.each anti-pattern)..."
cat > lib/generators/lightek/domain/templates/engine.rb.tt << 'EOF'
# frozen_string_literal: true
require "rails/engine"
module <%= @module %>
  class Engine < ::Rails::Engine
    isolate_namespace <%= @module %>

    # Register this domain's service with the kernel (lazy, call-time resolution).
    initializer "<%= @gem_name %>.register_service" do
      ActiveSupport.on_load(:action_controller_base) do
        Lightek::ServiceRegistry.register(:<%= @domain %>, <%= @service %>) if defined?(Lightek::ServiceRegistry)
      end
    end

    # Load THIS domain's helpers dynamically (drop a file in app/helpers/<%= @gem_name %>/
    # and it's picked up — no engine edit). Doctrine: dynamic reads, direct writes.
    initializer "<%= @gem_name %>.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper <%= @module %>::Engine.helpers
      end
    end

    # Register dashboard editor routes with dymond_dash BEFORE routes are drawn.
    initializer "<%= @gem_name %>.register_editor_routes", before: :add_routing_paths do
      require "<%= @gem_name %>/editor_routes"
      <%= @module %>::EditorRoutesRegistration.register!
    end

    # Migrations run in place (no install:migrations copy).
    initializer "<%= @gem_name %>.append_migrations" do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each { |p| app.config.paths["db/migrate"] << p }
      end
    end
  end
end
EOF

echo "Writing migration generator..."
mkdir -p lib/generators/lightek/migration
cat > lib/generators/lightek/migration/migration_generator.rb << 'EOF'
# frozen_string_literal: true
require "rails/generators"

module Lightek
  module Generators
    # Writes a real, timestamped migration straight into a domain gem's own
    # db/migrate — because `rails g migration` doesn't work inside these gems
    # (no app context, no bin/rails), and hand-writing timestamps doesn't scale.
    #
    #   rails g lightek:migration dymond_catalog create_widgets name:string price_cents:bigint
    #   rails g lightek:migration dymond_catalog add_featured_to_products featured:boolean
    #   rails g lightek:migration dymond_catalog remove_legacy_flag_from_products legacy_flag:boolean
    #
    # Recognizes create_/add_..._to_.../remove_..._from_... naming, same as
    # vanilla Rails. Anything else gets an empty `change` scaffold, still
    # timestamped and placed correctly, ready to hand-edit.
    class MigrationGenerator < Rails::Generators::Base
      argument :gem_name, type: :string, banner: "gem_name"
      argument :migration_name, type: :string, banner: "migration_name"
      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      class_option :path, type: :string, default: "~/Desktop/Development",
                   desc: "Where the gem repo lives"

      def create_migration_file
        gem_root = File.expand_path(File.join(options[:path], gem_name))
        unless Dir.exist?(gem_root)
          say_status :error, "Gem not found at #{gem_root}", :red
          return
        end

        ts        = Time.now.utc.strftime("%Y%m%d%H%M%S")
        mn        = migration_name.underscore
        class_name = mn.camelize
        filename  = "#{ts}_#{mn}.rb"
        full_path = File.join(gem_root, "db/migrate", filename)

        FileUtils.mkdir_p(File.dirname(full_path))
        File.write(full_path, build_body(class_name, mn))
        say_status :create, "#{gem_name}/db/migrate/#{filename}", :green
      end

      private

      def col_type(pair)
        _f, t = pair.split(":")
        t.presence || "string"
      end

      def col_name(pair)
        pair.split(":").first
      end

      def build_body(class_name, mn)
        if mn.start_with?("create_")
          table = mn.sub(/^create_/, "")
          cols = attributes.map { |a| "      t.#{col_type(a)} :#{col_name(a)}" }.join("\n")
          <<~RUBY
            # frozen_string_literal: true
            class #{class_name} < ActiveRecord::Migration[8.0]
              def change
                create_table :#{table} do |t|
            #{cols}
                  t.timestamps
                end
              end
            end
          RUBY
        elsif mn =~ /^add_.+_to_(.+)$/
          table = Regexp.last_match(1)
          cols = attributes.map { |a| "    add_column :#{table}, :#{col_name(a)}, :#{col_type(a)}" }.join("\n")
          <<~RUBY
            # frozen_string_literal: true
            class #{class_name} < ActiveRecord::Migration[8.0]
              def change
            #{cols}
              end
            end
          RUBY
        elsif mn =~ /^remove_.+_from_(.+)$/
          table = Regexp.last_match(1)
          cols = attributes.map { |a| "    remove_column :#{table}, :#{col_name(a)}, :#{col_type(a)}" }.join("\n")
          <<~RUBY
            # frozen_string_literal: true
            class #{class_name} < ActiveRecord::Migration[8.0]
              def change
            #{cols}
              end
            end
          RUBY
        else
          <<~RUBY
            # frozen_string_literal: true
            class #{class_name} < ActiveRecord::Migration[8.0]
              def change
              end
            end
          RUBY
        end
      end
    end
  end
end
EOF

echo ""
echo "Done. Next:"
echo "  git add -A"
echo "  git commit -m 'Fix Engine.helpers.each in domain template; add lightek:migration generator'"
echo "  git push"
echo ""
echo "Then in host app:"
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update lightek_kernel"
echo ""
echo "Usage going forward:"
echo "  bin/rails g lightek:migration dymond_catalog add_foo_to_products foo:string"
