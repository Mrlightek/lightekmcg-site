# frozen_string_literal: true
module NevaehOs
  module TaskModel
    module_function
    # Score only fixed labels with the real local neural network. No generated
    # Ruby, shell, resource names, account IDs or tool arguments are executable.
    def propose(actor,text)
      return unless defined?(NevaehLanguageModel) && NevaehLanguageModel.table_exists?
      model=NevaehLanguageModel.where(enabled:true).where.not(active_checkpoint_id:nil).order(:id).detect do |candidate|
        checkpoint=candidate.active_checkpoint
        provenance=checkpoint&.nevaeh_training_run&.snapshot&.dig('provenance')
        reviewed=Array(provenance&.fetch('reviewed_example_ids',[]))
        retained=reviewed.empty? || NevaehTaskExample.where(user:actor,status:'active',id:reviewed,catalog_sha256:TaskCatalog.fingerprint).count==reviewed.size
        measured=checkpoint&.metrics.to_h
        evaluated=checkpoint&.weights.to_h['task_head'].is_a?(Hash) && measured['acceptance_passed']==true && measured['task_label_heldout_examples']==10 && measured['task_label_accuracy'].is_a?(Numeric) && measured['task_label_accuracy']>=0.8
        evaluated && retained && candidate.available_to?(actor) && checkpoint&.status=='active' && provenance&.fetch('source',nil)=='ten_task_interpretation' && provenance['account_id']==actor.id && provenance['catalog_sha256']==TaskCatalog.fingerprint
      end
      return unless model
      checkpoint=model.active_checkpoint
      raise ArgumentError,'Task model checksum mismatch' unless checkpoint.sha256==Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(checkpoint.weights)) && checkpoint.nevaeh_language_model_id==model.id
      network=NevaehIntelligences::Neural::Network.new(checkpoint.weights)
      ranking=network.rank_labels(prompt:text,labels:TaskCatalog.keys)
      return if ranking.empty?
      best=ranking.first
      {task:best.fetch('label'),model_id:model.id,checkpoint_id:checkpoint.id,confidence:best.fetch('confidence'),
       candidates:ranking.first(3),requires_review:true}
    rescue ArgumentError => error
      {error:error.message,requires_review:true}
    end
  end
end
