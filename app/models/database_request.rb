# app/models/database_request.rb
class DatabaseRequest < ApplicationRecord
  belongs_to :requestable, polymorphic: true, optional: true

  after_create_commit :awaken_nevaeh

  private

  def awaken_nevaeh
    NevaehAwarenessJob.perform_later(self.id)
  end
end