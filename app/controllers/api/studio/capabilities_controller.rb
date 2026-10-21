# frozen_string_literal: true
module Api
  module Studio
    # STUDIO-203. Native Rails 8 signed-cookie sessions, not API bearer tokens.
    class CapabilitiesController < ::ApplicationController
      def index
        authorize! :read, ::NevaehCapability
        payload = ::Studio::Capabilities::RailsReadAdapter.read_authorized_database
        render json: payload
      rescue ::Studio::Capabilities::RailsReadAdapter::Invalid,
             ::Studio::Capabilities::Discovery::Invalid
        render json: { error: 'capability discovery unavailable' }, status: :unprocessable_entity
      end
    end
  end
end
