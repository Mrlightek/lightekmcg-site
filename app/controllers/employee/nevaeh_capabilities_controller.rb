# frozen_string_literal: true
module Employee
  class NevaehCapabilitiesController < Employee::ApplicationController
    before_action :authorize_console!

    def index
      @capabilities = NevaehIntelligences::CapabilityConsoleV7a.list
      respond_to do |format|
        format.html
        format.json { render json: { capabilities: @capabilities, read_only: true } }
      end
    end

    def show
      @key = params.require(:key).to_s
      @detail = NevaehIntelligences::CapabilityConsoleV7a.detail(key: @key)
      respond_to do |format|
        format.html
        format.json { render json: @detail }
      end
    end

    def services
      @services = NevaehIntelligences::CapabilityConsoleV7a.services
      respond_to do |format|
        format.html
        format.json { render json: { services: @services, read_only: true } }
      end
    end

    private

    def authorize_console!
      authorize! :read, Marlon::Ticket
    end
  end
end
