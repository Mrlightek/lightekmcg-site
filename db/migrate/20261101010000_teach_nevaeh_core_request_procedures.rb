# frozen_string_literal: true
class TeachNevaehCoreRequestProcedures < ActiveRecord::Migration[8.0]
  def up
    NevaehIntelligences::StructuredTicket.registered!
    NevaehIntelligences::TeachCoreProcedures.call
  end

  def down
    # Keep instance knowledge, evidence, and pinned ticket revisions intact.
  end
end
