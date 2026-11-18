module Studio
  module Compute
    class Queue
      def self.economy?(operation)
        operation.provider == "blender" && CpuProfile.economy?(operation.manifest)
      end

      def self.name(operation)
        return "studio" if Federation::Dispatch.enabled?(operation)
        return "studio" unless economy?(operation) && dedicated?
        dedicated_name
      end

      def self.dedicated_name
        raise ArgumentError, "Dedicated CPU workers require shared Studio storage" unless shared_storage?
        "studio_cpu"
      end

      def self.dedicated? = ENV["STUDIO_CPU_DEDICATED_QUEUE"] == "1"
      def self.shared_storage? = ENV["STUDIO_CPU_SHARED_STORAGE"] == "1"
      def self.worker? = ENV["STUDIO_CPU_WORKER"] == "1"
    end
  end
end
