# frozen_string_literal: true
module Employee
  class NevaehControlCenterController < Employee::ApplicationController
    before_action { authorize! :read, Marlon::Ticket }
    before_action :authorize_builder!, except: :index

    def index
      load_workspace
      respond_to do |format|
        format.html
        format.json { render json: {workflows: @workflows, capabilities: @runtime_capabilities, runs: @runs.map { |run| {id: run.id, workflow_id: run.nevaeh_workflow_id, ticket_id: run.ticket_id, status: run.execution_status, error: run.error} }, profiles: @profiles, inference_models: @inference_models} }
      end
    end

    def save_workflow
      @workflow = params[:id].present? ? NevaehWorkflow.find(params[:id]) : NevaehWorkflow.new(creator: current_user)
      values = params.require(:workflow).permit(:name, :description, :status, :interval_minutes, :lock_version)
      raw = params.require(:sections_json).to_s
      raise ArgumentError, "Workflow definition is too large" if raw.bytesize > 100000
      @workflow.assign_attributes(values)
      @workflow.sections = JSON.parse(raw)
      @workflow.save!
      redirect_to employee_nevaeh_control_center_path(tab: "workers", workflow_id: @workflow.id), notice: "Worker saved. #{@workflow.status.humanize}."
    rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
      load_workspace(preserve: true)
      @builder_error = error.is_a?(ActiveRecord::StaleObjectError) ? "This worker changed in another editor. Reload before saving." : error.message
      render :index, status: :unprocessable_entity
    end

    def run
      workflow = NevaehWorkflow.find(params[:id])
      run = NevaehIntelligences::WorkflowRunner.request!(workflow: workflow, actor: current_user, request_key: params.require(:request_key))
      NevaehIntelligences::WorkflowRunJob.perform_later(run.id)
      redirect_to employee_nevaeh_control_center_path(tab: "runs"), notice: "Run ##{run.id} queued. Its ticket will show execution and acceptance evidence."
    rescue NevaehIntelligences::WorkOrder::Invalid => error
      redirect_to employee_nevaeh_control_center_path(tab: "workers"), alert: error.message
    end

    def save_profile
      @profile = params[:id].present? ? NevaehWritingProfile.find(params[:id]) : NevaehWritingProfile.new
      values = params.require(:profile).permit(:name, :format, :provider, :inference_model_id, :instructions, :enabled, :lock_version)
      @profile.assign_attributes(values)
      @profile.templates = params[:templates].to_s.lines.map(&:strip).reject(&:empty?)
      @profile.examples = params[:examples].to_s.split(/\n\s*---\s*\n/).map(&:strip).reject(&:empty?)
      @profile.save!
      redirect_to employee_nevaeh_control_center_path(tab: "writing", profile_id: @profile.id), notice: "Writing service saved. Studio can use this profile immediately."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
      load_workspace(preserve: true)
      @builder_error = error.is_a?(ActiveRecord::StaleObjectError) ? "This profile changed in another editor. Reload before saving." : error.message
      render :index, status: :unprocessable_entity
    end

    def generate
      profile = NevaehWritingProfile.where(enabled: true).find(params[:profile_id]) if params[:profile_id].present?
      context = params.require(:context).permit(*NevaehIntelligences::WritingEngine::TOKENS).to_h
      result = NevaehIntelligences::WritingEngine.generate(format: params.require(:format), context: context, profile: profile&.contract)
      render json: result
    rescue ArgumentError => error
      render json: {error: error.message}, status: :unprocessable_entity
    end

    def save_model
      @inference_model = params[:id].present? ? NevaehInferenceModel.find(params[:id]) : NevaehInferenceModel.new
      @inference_model.assign_attributes(params.require(:inference_model).permit(:name, :description, :enabled, :lock_version))
      %w[rules examples lexicon].each do |field|
        raw = params.require("#{field}_json").to_s
        raise ArgumentError, "Inference data is too large" if raw.bytesize > 250000
        @inference_model.public_send("#{field}=", JSON.parse(raw))
      end
      @inference_model.save!
      redirect_to employee_nevaeh_control_center_path(tab: "models", model_id: @inference_model.id), notice: "Inference model saved. Its rules and examples are available immediately."
    rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
      load_workspace(preserve: true)
      @builder_error = error.is_a?(ActiveRecord::StaleObjectError) ? "This model changed in another editor. Reload before saving." : error.message
      render :index, status: :unprocessable_entity
    end

    def infer
      model = NevaehInferenceModel.find(params[:id])
      raise ArgumentError, "This inference model is disabled" unless model.enabled?
      render json: model.infer(format: params.require(:format), context: params.require(:context).permit(*NevaehIntelligences::WritingEngine::TOKENS).to_h)
    rescue ArgumentError => error
      render json: {error: error.message}, status: :unprocessable_entity
    end

    def sample_context
      # Faker provides bounded fictional fixtures, not prose or factual knowledge.
      require "faker"
      render json: {protagonist: Faker::Name.first_name, companion: Faker::Name.first_name,
        setting: "COMMUNITY STUDIO", topic: "opening night", goal: "finish the first show",
        obstacle: "a missing rehearsal", facts: "The team has one rehearsal slot left.", audience: "local creators"}
    end

    private

    def authorize_builder!
      authorize! :manage, NevaehWorkflow
    end

    def load_workspace(preserve: false)
      @workflows = NevaehWorkflow.order(updated_at: :desc).limit(100)
      @runtime_capabilities = NevaehCapability.order(:domain, :name).limit(500)
      @runs = NevaehWorkflowRun.includes(:nevaeh_workflow, :ticket).order(id: :desc).limit(50)
      @profiles = NevaehWritingProfile.order(:name).limit(100)
      @inference_models = NevaehInferenceModel.order(:name).limit(100)
      @inference_model = nil unless preserve
      @inference_model ||= params[:model_id].present? ? NevaehInferenceModel.find(params[:model_id]) : NevaehInferenceModel.new(rules: [], examples: [], lexicon: {}, enabled: true)
      @workflow = nil unless preserve
      @profile = nil unless preserve
      @workflow ||= params[:workflow_id].present? ? NevaehWorkflow.find(params[:workflow_id]) : NevaehWorkflow.new(status: "draft", sections: [{"id" => "project", "action" => "studio.project.create", "inputs" => {"name" => "New production"}, "depends_on" => []}])
      @profile ||= params[:profile_id].present? ? NevaehWritingProfile.find(params[:profile_id]) : NevaehWritingProfile.new(format: "script", provider: "rules", templates: [], examples: [], enabled: true)
      @tab = params[:tab].presence || (action_name == "save_profile" ? "writing" : action_name == "save_model" ? "models" : "workers")
      @tab = "workers" unless %w[workers capabilities runs writing models navigation].include?(@tab)
    end
  end
end
