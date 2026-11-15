module Studio
  module Compute
    class Queue
      def self.economy?(operation)
        operation.provider == "blender" && CpuProfile.economy?(operation.manifest)
      end

      def self.name(operation)
        return "studio" unless economy?(operation) && dedicated?
        raise ArgumentError, "Dedicated CPU workers require shared Studio storage" unless ENV["STUDIO_CPU_SHARED_STORAGE"] == "1"
        "studio_cpu"
      end

      def self.dedicated? = ENV["STUDIO_CPU_DEDICATED_QUEUE"] == "1"
      def self.worker? = ENV["STUDIO_CPU_WORKER"] == "1"
    end
  end
end
