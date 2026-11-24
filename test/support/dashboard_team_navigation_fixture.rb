# frozen_string_literal: true

# Standalone view harnesses lack the employment schema. Supply the result of its
# scope, keeping the navigation role and link logic under test.
module LightekTeam
  class Workspace
    def self.employers_for(actor)
      Scope.new(%w[super_admin admin white_label].include?(actor.role))
    end

    Scope = Struct.new(:exists?)
  end
end
