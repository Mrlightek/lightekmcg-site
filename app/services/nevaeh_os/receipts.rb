# frozen_string_literal: true
module NevaehOs
  module Receipts
    module_function
    # A successful submission is distinct from a verified downstream operation.
    def for(action)
      value = {id:action.id,status:action.status,result:action.result,error:action.error,created_at:action.created_at,kind:action.command['kind']}
      return value unless action.status == 'completed'
      if action.command['kind']=='production' && action.result['rehearsal_id']
        service=Studio::Director::Rehearsal
        receipt=service.receipt(service.find!(action.result['rehearsal_id'],actor:action.user),actor:action.user)
        value[:downstream]={type:'rehearsal',id:receipt['rehearsal_id'],status:receipt['status'],result:receipt}
        value[:status]=%w[pending running].include?(receipt['status']) ? 'dispatched' : %w[failed needs_attention].include?(receipt['status']) ? 'failed' : 'completed'
      elsif action.command['kind'] == 'production' && action.result['production_id']
        producer = Studio::Director::Producer
        receipt = producer.receipt(producer.find!(action.result['production_id'], actor: action.user), actor: action.user)
        value[:downstream] = {type:'directed_production', id:receipt['production_id'], status:receipt['status'], result:receipt}
        value[:status] = receipt['status'] == 'dispatched' ? 'dispatched' : receipt['status'] == 'needs_attention' ? 'failed' : 'completed'
      elsif action.command['kind'] == 'campaign_produce' && action.result['operation_id']
        producer = LightekMarketing::CampaignProducer
        operation = producer.find!(action.result['operation_id'], actor: action.user)
        receipt = producer.receipt(operation, actor: action.user)
        value[:downstream] = {type:'campaign_production', id:operation.id, status:operation.status, error:operation.error_message, result:receipt}
        value[:status] = %w[completed failed cancelled].include?(operation.status) ? operation.status : 'dispatched'
      elsif action.result['agent_run_id']
        run=NevaehAgentRun.where(actor:action.user).find(action.result['agent_run_id'])
        child=run.nevaeh_os_action
        value[:downstream]=child ? self.for(child) : {type:'agent',id:run.id,status:run.status,error:run.error}
        value[:status]=run.execution_status
      elsif action.result['work_item_id']
        item = DymondDispatch::WorkItem.find(action.result['work_item_id'])
        value[:downstream] = {type:'dispatch',id:item.id,status:item.status,result:item.result,error:item.error}
        value[:status] = item.done? ? 'completed' : item.failed? ? 'failed' : 'dispatched'
      elsif action.result['run_id']
        run = NevaehWorkflowRun.where(actor:action.user).find(action.result['run_id'])
        value[:downstream] = {type:'workflow',id:run.id,ticket_id:run.ticket_id,status:run.execution_status,error:run.error}
        value[:status] = run.execution_status == 'verified' ? 'completed' : %w[blocked failed error].include?(run.execution_status) ? 'failed' : 'dispatched'
      elsif action.result['training_run_id']
        run = NevaehTrainingRun.where(actor:action.user).find(action.result['training_run_id'])
        value[:downstream] = {type:'training',id:run.id,status:run.status,metrics:run.metrics,error:run.error}
        value[:status] = %w[completed failed cancelled].include?(run.status) ? run.status : 'dispatched'
      end
      value
    rescue ActiveRecord::RecordNotFound
      value.merge(status:'evidence_unavailable',error:'The downstream execution record is unavailable. Submission alone is not proof of completion.')
    end
  end
end
