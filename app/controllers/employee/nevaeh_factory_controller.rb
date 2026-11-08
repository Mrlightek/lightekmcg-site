# frozen_string_literal: true
module Employee
  class NevaehFactoryController < Employee::ApplicationController
    before_action do
      authorize! :manage, NevaehWorkflow
      response.set_header('Cache-Control', 'private, no-store')
    end
    rescue_from ArgumentError, JSON::ParserError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError do |error|
      redirect_back fallback_location: employee_nevaeh_factory_path, alert: error.is_a?(ActiveRecord::StaleObjectError) ? 'This record changed in another editor. Reload before saving.' : error.message
    end
    rescue_from NevaehIntelligences::SoftwareLibrary::Missing do
      head :not_found
    end
    def index
      @tab = %w[construction training conversation].include?(params[:tab]) ? params[:tab] : 'construction'
      @constructions = NevaehConstruction.includes(:active_release).order(updated_at: :desc).limit(100)
      @construction = params[:construction_id].present? ? NevaehConstruction.find(params[:construction_id]) : NevaehConstruction.new(definition: default_definition, sample_tests: default_tests)
      @datasets = NevaehTrainingDataset.order(updated_at: :desc).limit(100)
      @dataset = params[:dataset_id].present? ? NevaehTrainingDataset.find(params[:dataset_id]) : NevaehTrainingDataset.new(examples: [])
      @models = NevaehLanguageModel.order(:name).limit(100)
      @language_model = params[:language_model_id].present? ? NevaehLanguageModel.find(params[:language_model_id]) : NevaehLanguageModel.new(hidden_size: 16, vocabulary_limit: 256, visibility: 'internal')
      @training_runs = NevaehTrainingRun.includes(:checkpoint, :nevaeh_language_model, :nevaeh_training_dataset).order(id: :desc).limit(10)
      @conversations = NevaehConversation.where(user: current_user).order(updated_at: :desc).limit(30)
      @conversation = @conversations.find(params[:conversation_id]) if params[:conversation_id].present?
      @documents = NevaehIntelligences::SoftwareLibrary.new.documents.map { |doc| doc.slice(:id, :title, :path) }
    end
    def save_construction
      record = params[:id].present? ? NevaehConstruction.find(params[:id]) : NevaehConstruction.new(creator: current_user)
      record.assign_attributes(params.require(:construction).permit(:name, :key, :description, :lock_version))
      record.definition = parse_json(:definition_json, 100000)
      record.sample_tests = parse_json(:tests_json, 100000)
      record.save!
      redirect_to employee_nevaeh_factory_path(construction_id: record.id), notice: 'Construction draft saved. Build to generate and verify its implementation.'
    end
    def build
      release = NevaehIntelligences::Factory::Compiler.build!(construction: NevaehConstruction.find(params[:id]), actor: current_user)
      redirect_to employee_nevaeh_factory_path(construction_id: release.nevaeh_construction_id), notice: "Release v#{release.version}: #{release.status}."
    end
    def activate
      release = NevaehConstructionRelease.find(params[:id])
      NevaehIntelligences::Factory::Compiler.activate!(release: release, actor: current_user)
      redirect_to employee_nevaeh_factory_path(construction_id: release.nevaeh_construction_id), notice: 'Capability connected and active. Its worker and verifier are ready.'
    end
    def pause
      record = NevaehConstruction.find(params[:id])
      record.with_lock do
        record.update!(status: 'paused')
        NevaehCapability.where(slug: record.capability_key).update_all(enabled: false)
      end
      redirect_to employee_nevaeh_factory_path(construction_id: record.id), notice: 'Construction paused. Reactivate a verified release to resume.'
    end
    def create_worker
      release = NevaehConstructionRelease.find(params[:id])
      raise ArgumentError, 'Activate this construction before creating a worker' unless release.status == 'active' && release.nevaeh_construction.status == 'active'
      data = parse_json(:inputs_json, 16000)
      NevaehIntelligences::Factory::Contract.inputs!(release.definition.fetch('input_schema'), data)
      worker = NevaehWorkflow.create!(creator: current_user, name: params[:worker_name].presence || release.nevaeh_construction.name,
        status: 'active', interval_minutes: params[:interval_minutes].presence,
        sections: [{'id' => 'constructed_service', 'action' => 'factory.construct.execute', 'inputs' => {'release_id' => release.id, 'data' => data}, 'depends_on' => []}])
      if params[:run_now] == '1'
        run = NevaehIntelligences::WorkflowRunner.request!(workflow: worker, actor: current_user, request_key: SecureRandom.uuid)
        NevaehIntelligences::WorkflowRunJob.perform_later(run.id)
      end
      redirect_to employee_nevaeh_control_center_path(tab: 'workers', workflow_id: worker.id), notice: 'Constructed worker saved in Nevaeh’s workforce.'
    end
    def artifacts
      release = NevaehConstructionRelease.find(params[:id])
      send_data JSON.pretty_generate({capability: release.nevaeh_construction.capability_key, release: release.version, fingerprint: release.fingerprint, files: release.artifacts, verification: release.verification}), type: 'application/json', disposition: 'attachment', filename: "nevaeh-#{release.nevaeh_construction.key}-v#{release.version}.json"
    end
    def save_dataset
      dataset = params[:id].present? ? NevaehTrainingDataset.find(params[:id]) : NevaehTrainingDataset.new(creator: current_user)
      dataset.assign_attributes(params.require(:dataset).permit(:name, :lock_version))
      dataset.examples = parse_json(:examples_json, 262144)
      dataset.status = 'draft'
      dataset.save!
      redirect_to employee_nevaeh_factory_path(tab: 'training', dataset_id: dataset.id), notice: 'Dataset saved for review. Approve it before training.'
    end
    def generate_dataset
      result = if params[:document_id].present?
        doc = NevaehIntelligences::SoftwareLibrary.new.find(params[:document_id])
        NevaehIntelligences::Neural::CorpusFactory.from_document(doc)
      else
        NevaehIntelligences::Neural::CorpusFactory.generate(count: params[:count].presence || 40, topic: params[:topic].presence || 'Studio')
      end
      dataset = NevaehTrainingDataset.create!(creator: current_user, name: params[:name].presence || 'Generated conversation examples', examples: result[:examples], provenance: result[:provenance])
      redirect_to employee_nevaeh_factory_path(tab: 'training', dataset_id: dataset.id), notice: 'Examples generated. Review their text and provenance, then approve.'
    end
    def approve_dataset
      dataset = NevaehTrainingDataset.find(params[:id])
      dataset.update!(status: 'approved')
      redirect_to employee_nevaeh_factory_path(tab: 'training', dataset_id: dataset.id), notice: 'Dataset approved for explicit training requests.'
    end
    def save_language_model
      model = params[:id].present? ? NevaehLanguageModel.find(params[:id]) : NevaehLanguageModel.new
      model.assign_attributes(params.require(:language_model).permit(:name, :description, :hidden_size, :vocabulary_limit, :visibility, :enabled, :lock_version))
      model.save!
      redirect_to employee_nevaeh_factory_path(tab: 'training', language_model_id: model.id), notice: 'Native language model saved.'
    end
    def train
      model = NevaehLanguageModel.find(params[:id])
      run = NevaehIntelligences::Neural::Training.request!(model: model, dataset: NevaehTrainingDataset.find(params.require(:dataset_id)), actor: current_user,
        epochs: params.require(:epochs), request_key: params.require(:request_key))
      NevaehIntelligences::Neural::TrainingJob.perform_later(run.id)
      redirect_to employee_nevaeh_factory_path(tab: 'training', language_model_id: model.id), notice: "Training run ##{run.id} queued. Refresh to inspect its loss and checkpoint."
    end
    def cancel_training
      run = NevaehTrainingRun.find(params[:id])
      run.with_lock { run.update!(status: 'cancelled', lease_token: nil) if run.status.in?(%w[queued running]) }
      redirect_to employee_nevaeh_factory_path(tab: 'training'), notice: 'Training cancellation recorded. The worker stops at its next epoch boundary.'
    end
    def activate_checkpoint
      checkpoint = NevaehLanguageCheckpoint.find(params[:id])
      NevaehIntelligences::Neural::Training.activate!(checkpoint: checkpoint, actor: current_user)
      redirect_to employee_nevaeh_factory_path(tab: 'training', language_model_id: checkpoint.nevaeh_language_model_id), notice: 'Checkpoint activated. Conversation and neural writing services now use these weights.'
    end
    def conversation
      model = NevaehLanguageModel.find(params.require(:language_model_id))
      raise ArgumentError, 'Activate a checkpoint before opening a conversation' unless model.enabled? && model.active_checkpoint
      record = NevaehConversation.create!(user: current_user, nevaeh_language_model: model, title: params[:title].presence || 'Conversation')
      redirect_to employee_nevaeh_factory_path(tab: 'conversation', conversation_id: record.id)
    end
    def reply
      conversation = NevaehConversation.where(user: current_user).find(params[:id])
      conversation.reply!(actor: current_user, prompt: params.require(:prompt), request_key: params.require(:request_key))
      redirect_to employee_nevaeh_factory_path(tab: 'conversation', conversation_id: conversation.id)
    end
    private
    def parse_json(key, max)
      raw = params.require(key).to_s
      raise ArgumentError, 'Submitted definition is too large' if raw.bytesize > max
      JSON.parse(raw)
    end
    def default_definition
      {'input_schema' => {'name' => 'string'}, 'steps' => [{'op' => 'normalize', 'field' => 'name', 'mode' => 'strip'}, {'op' => 'template', 'field' => 'greeting', 'text' => 'Welcome, {name}.'}, {'op' => 'require', 'fields' => %w[name greeting]}]}
    end
    def default_tests = [{'inputs' => {'name' => '  Marlon  '}, 'expected' => {'name' => 'Marlon', 'greeting' => 'Welcome, Marlon.'}}]
  end
end
