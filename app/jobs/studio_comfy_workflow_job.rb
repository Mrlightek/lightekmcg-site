# frozen_string_literal: true
class StudioComfyWorkflowJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.where(capability:Studio::Workflows::Production::CAPABILITY).find(id)
    if operation.terminal?
      Studio::Workflows::Production.cancel_child(operation) unless operation.status=="completed"
      return
    end
    raise ArgumentError,"The workflow expired. Check the worker before submitting a new draft." if operation.created_at<1.hour.ago
    runtime=Studio::Ai::Runtime.new(site:operation.studio_project.site,identity:operation.metadata.fetch("workflow_worker"))
    operation.with_lock do
      if operation.status=="pending"
        # A lost submit response is uncertain; never blindly submit a second graph.
        operation.update!(status:"running",metadata:operation.metadata.merge("workflow_phase"=>"submitting"))
        prompt_id=runtime.submit(Studio::Workflows::Production.graph(operation))
        operation.update!(metadata:operation.metadata.merge("workflow_prompt_id"=>prompt_id,"workflow_phase"=>"waiting_for_comfyui"))
      end
    end
    prompt_id=operation.metadata["workflow_prompt_id"]
    raise ArgumentError,"ComfyUI submission is uncertain. Check the worker before retrying." unless prompt_id
    output=runtime.result(prompt_id)
    if output&.dig("status","status_str")=="error"
      raise ArgumentError,"The ComfyUI workflow failed. Check the render operation and worker connection."
    end
    if output&.dig("status","completed")
      operation.with_lock do
        return if operation.terminal?
        saved=Studio::Workflows::Production.result(operation)
        proof=Array(output.dig("outputs","4","lightek_studio")).first
        raise ArgumentError,"ComfyUI did not confirm this job's saved artifact" unless proof.is_a?(Hash) && proof["artifact_id"]==saved[:artifact_id] && proof["operation_id"]==operation.id
        operation.update!(status:"completed",completed_at:Time.current,metadata:operation.metadata.merge("workflow_phase"=>"completed"))
      end
    else
      self.class.set(wait:5.seconds).perform_later(id)
    end
  rescue StandardError=>error
    operation&.with_lock do
      unless operation.terminal?
        operation.update!(status:"failed",error_message:error.is_a?(ArgumentError) ? error.message.first(500) : "The ComfyUI workflow connection failed. Check the worker before retrying.")
        Studio::Workflows::Production.cancel_child(operation)
      end
    end
  end
end
