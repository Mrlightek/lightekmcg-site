require "rails_helper"

RSpec.describe JobItemsController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/job_items").to route_to("job_items#index")
    end

    it "routes to #new" do
      expect(get: "/job_items/new").to route_to("job_items#new")
    end

    it "routes to #show" do
      expect(get: "/job_items/1").to route_to("job_items#show", id: "1")
    end

    it "routes to #edit" do
      expect(get: "/job_items/1/edit").to route_to("job_items#edit", id: "1")
    end


    it "routes to #create" do
      expect(post: "/job_items").to route_to("job_items#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/job_items/1").to route_to("job_items#update", id: "1")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/job_items/1").to route_to("job_items#update", id: "1")
    end

    it "routes to #destroy" do
      expect(delete: "/job_items/1").to route_to("job_items#destroy", id: "1")
    end
  end
end
