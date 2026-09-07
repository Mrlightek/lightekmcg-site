require "rails_helper"

RSpec.describe SystemJobsController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/system_jobs").to route_to("system_jobs#index")
    end

    it "routes to #new" do
      expect(get: "/system_jobs/new").to route_to("system_jobs#new")
    end

    it "routes to #show" do
      expect(get: "/system_jobs/1").to route_to("system_jobs#show", id: "1")
    end

    it "routes to #edit" do
      expect(get: "/system_jobs/1/edit").to route_to("system_jobs#edit", id: "1")
    end


    it "routes to #create" do
      expect(post: "/system_jobs").to route_to("system_jobs#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/system_jobs/1").to route_to("system_jobs#update", id: "1")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/system_jobs/1").to route_to("system_jobs#update", id: "1")
    end

    it "routes to #destroy" do
      expect(delete: "/system_jobs/1").to route_to("system_jobs#destroy", id: "1")
    end
  end
end
