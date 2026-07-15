# frozen_string_literal: true

module Marlon
  module Blueprint
    class Resolver
      class CircularDependencyError < StandardError; end

      def initialize(capability_packs)
        @capability_packs = Array(capability_packs)
      end

      def resolve
        resolved = []
        visiting = []

        @capability_packs.each do |pack|
          visit(pack, resolved:, visiting:)
        end

        resolved
      end

      private

      def visit(pack, resolved:, visiting:)
        return if resolved.include?(pack)

        if visiting.include?(pack)
          cycle = (visiting.drop_while { |item| item != pack } + [pack]).map(&:key)
          raise CircularDependencyError, "Circular capability dependency: #{cycle.join(' -> ')}"
        end

        visiting << pack
        pack.dependencies.order(:key).each do |dependency|
          visit(dependency, resolved:, visiting:)
        end
        visiting.pop
        resolved << pack
      end
    end
  end
end
