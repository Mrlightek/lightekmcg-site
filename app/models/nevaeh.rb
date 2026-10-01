class Nevaeh < ApplicationRecord
    include NevaehConcern

    # Universal Lightek orchestration front door.
    def self.handle(**attributes)
      NevaehOrchestration::Orchestrator.call(**attributes)
    end

    #Response method, returns all Nevaeh responses, reporting, jobs, etc.
    def self response
    end

    #Method to start listening to the network
    def self start
        #In here we start the listener from the listener service or the nevaeh concern
    end
end
