# frozen_string_literal: true

require "rails/generators"

module Nevaeh
  module Generators
    class MacroGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :helpers,
               type: :array,
               default: [],
               banner: "helper helper ..."

      desc <<~DESC
        Creates a Nevaeh macro and installs it into NevaehConcern.

        Examples:

          rails g nevaeh:macro tracks_network_requests

          rails g nevaeh:macro tracks_database_requests \
            record_database_request \
            database_request_count

        Generated macros live in:

          app/models/concerns/nevaeh/macros/

        NevaehConcern automatically includes the macro.
      DESC

      def create_macro_directory
        empty_directory "app/models/concerns/nevaeh/macros"
      end

      def create_macro
        template(
          "macro.rb.tt",
          "app/models/concerns/nevaeh/macros/#{file_name}.rb"
        )
      end

      def install_macro
        concern_path = "app/models/concerns/nevaeh_concern.rb"

        unless File.exist?(concern_path)
          say_status(
            :error,
            "#{concern_path} does not exist",
            :red
          )

          return
        end

        require_line =
          %(require_relative "nevaeh/macros/#{file_name}")

        inject_into_file(
          concern_path,
          "#{require_line}\n",
          before: "module NevaehConcern"
        ) unless File.read(concern_path).include?(require_line)

        include_line =
          "    include Nevaeh::Macros::#{class_name}"

        inject_into_file(
          concern_path,
          "#{include_line}\n",
          after: "class_methods do\n"
        ) unless File.read(concern_path).include?(include_line)
      end

      private

      def macro_method_name
        file_name
      end

      def helper_method_names
        helpers.map(&:underscore)
      end
    end
  end
end
