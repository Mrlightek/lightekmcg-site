# frozen_string_literal: true
module Employee
  class NevaehGeneratorController < Employee::ApplicationController
    before_action :authorize_generator!
    before_action :local_only!
    def index
      @definitions = NevaehIntelligences::YamlCapabilityRegistryV7a.list(root: Rails.root.to_s)
      @plan = nil
      if params[:key].present?
        @plan = NevaehIntelligences::CapabilityCodeGeneratorV7a.plan(root: Rails.root.to_s, key: params[:key].to_s)
      end
      respond_to do |format|
        format.html
        format.json { render json: { capabilities: @definitions, plan: @plan, executable: false } }
      end
    rescue NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid, NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid => e
      render plain: e.message, status: :unprocessable_entity
    end
    def create
      key = params.require(:key).to_s
      # A unique server-side location outside the repo; do not accept browser file paths.
      require "tmpdir"
      require "securerandom"
      destination = File.join(Dir.tmpdir, "nevaeh-draft-#{SecureRandom.hex(12)}")
      manifest = NevaehIntelligences::CapabilityCodeGeneratorV7a.generate(root: Rails.root.to_s, key: key, destination: destination)
      render json: { draft: true, executable: false, destination: destination, manifest: manifest }, status: :created
    rescue NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid, NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
    private
    def authorize_generator!
      authorize! :manage, Marlon::Ticket
    end
    def local_only!
      head :forbidden unless Rails.env.development? || Rails.env.test?
    end
  end
end
