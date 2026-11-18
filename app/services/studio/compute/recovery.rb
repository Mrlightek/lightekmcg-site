# frozen_string_literal: true

module Studio
  module Compute
    module Recovery
      module_function

      def memory_error?(value)
        value.to_s.match?(/out of (?:gpu )?memory|cuda.*oom|outofmemoryerror|not enough (?:gpu )?memory|\bvram\b/i)
      end

      def advice(asset:, operation:, work_error:, checkpoint:)
        if checkpoint
          missing=operation.error_message.to_s.match?(/missing|checkpoint|frame artifact/i)
          return {message:missing ? "Some frames need rebuilding. Resume to keep the valid frames and render the rest." :
            "The renderer stopped before finishing. Resume to reuse any frames it saved."}
        end
        if asset&.status=="failed" && asset.metadata["ai_recovery"]=="economy"
          return {message:"The GPU ran short on memory. Try Economy at up to 512 pixels and no more than 20 steps.",action:"retry_economy"} unless asset.metadata["ai_profile"]=="economy"
          return {message:"Even Economy ran short on memory. Free GPU memory or choose another CUDA worker before retrying."}
        end
        if asset&.status=="failed" && asset.metadata["ai_performance_image"]
          return {message:"The CPU performance worker couldn’t finish. Try a shorter source and driving clip, up to 15 seconds each."}
        end
        if work_error.to_s.include?("at least 8 GiB total and 4 GiB free")
          return {message:"Wan needs at least 8 GiB total and 4 GiB free VRAM. Free memory or choose another CUDA worker."}
        end
        if work_error && memory_error?(work_error)
          return {message:"The worker couldn’t fit this job in memory. Try Economy or a worker with more free memory."}
        end
        nil
      end
    end
  end
end
