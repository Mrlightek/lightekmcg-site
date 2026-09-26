module Gatekeeper
  class InfrastructureController < ApplicationController
    def index
      redirect_to main_app.dashboard_infrastructure_path, status: :see_other
    end
  end
end
