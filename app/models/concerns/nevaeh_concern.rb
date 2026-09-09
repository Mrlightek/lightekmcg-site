# app/models/concerns/nevaeh_concern.rb

module NevaehConcern
  extend ActiveSupport::Concern

  class_methods do
    def tracks_unique_visits
      has_many :profile_visits, dependent: :destroy

      define_method(:record_visit_from) do |visitor|
        return if user_id == visitor.id

        profile_visits.find_or_create_by(user: visitor)
      end

      define_method(:unique_visits_count) do
        profile_visits.count
      end
    end

    def tracks_network_requests
      has_many :network_requests,
               as: :requestable,
               dependent: :destroy

      define_method(:record_network_request) do |**attributes|
        network_requests.create!(
          {
            occurred_at: Time.current
          }.merge(attributes)
        )
      end

      define_method(:network_request_count) do
        network_requests.count
      end

      define_method(:successful_network_request_count) do
        network_requests.where(success: true).count
      end

      define_method(:failed_network_request_count) do
        network_requests.where(success: false).count
      end
    end

    def tracks_database_requests
      has_many :database_requests,
               as: :requestable,
               dependent: :destroy

      define_method(:record_database_request) do |**attributes|
        database_requests.create!(
          {
            occurred_at: Time.current
          }.merge(attributes)
        )
      end

      define_method(:database_request_count) do
        database_requests.count
      end

      define_method(:successful_database_request_count) do
        database_requests.where(success: true).count
      end

      define_method(:failed_database_request_count) do
        database_requests.where(success: false).count
      end
    end
  end
end