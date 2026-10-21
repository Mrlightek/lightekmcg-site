# frozen_string_literal: true
module Employee
  class NevaehConfigurationController < Employee::ApplicationController
    before_action :authorize_configuration!
    before_action :require_local_configuration!

    def index
      @definitions = registry.list(root: Rails.root.to_s)
      respond_to do |format|
        format.html
        format.json { render json: { capabilities: @definitions, executable: false } }
      end
    rescue NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid => e
      render plain: e.message, status: :unprocessable_entity
    end

    def create
      result = registry.create(root: Rails.root.to_s, key: params.require(:key).to_s, write: true)
      redirect_to employee_nevaeh_configuration_path, notice: "Draft #{result.dig('capability', 'key')} created (disabled)."
    rescue NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, ActionController::ParameterMissing => e
      redirect_to employee_nevaeh_configuration_path, alert: "Draft rejected: #{e.message}"
    end

    def add_job
      deps = params[:after].to_s.split(',').map(&:strip).reject(&:empty?)
      result = registry.add_job(root: Rails.root.to_s, key: params.require(:key).to_s,
        id: params.require(:job_id).to_s, service: params.require(:service).to_s, after: deps, write: true)
      redirect_to employee_nevaeh_configuration_path, notice: "Job saved for #{result.dig('capability', 'key')} (disabled)."
    rescue NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, ActionController::ParameterMissing => e
      redirect_to employee_nevaeh_configuration_path, alert: "Job rejected: #{e.message}"
    end

    private

    def registry
      NevaehIntelligences::YamlCapabilityRegistryV7a
    end

    def authorize_configuration!
      authorize! :manage, Marlon::Ticket
    end

    def require_local_configuration!
      head :forbidden if Rails.env.production?
    end
  end
end
