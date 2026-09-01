require "rails_helper"

RSpec.describe NevaehsController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/nevaehs").to route_to("nevaehs#index")
    end

    it "routes to #new" do
      expect(get: "/nevaehs/new").to route_to("nevaehs#new")
    end

    it "routes to #show" do
      expect(get: "/nevaehs/1").to route_to("nevaehs#show", id: "1")
    end

    it "routes to #edit" do
      expect(get: "/nevaehs/1/edit").to route_to("nevaehs#edit", id: "1")
    end


    it "routes to #create" do
      expect(post: "/nevaehs").to route_to("nevaehs#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/nevaehs/1").to route_to("nevaehs#update", id: "1")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/nevaehs/1").to route_to("nevaehs#update", id: "1")
    end

    it "routes to #destroy" do
      expect(delete: "/nevaehs/1").to route_to("nevaehs#destroy", id: "1")
    end
  end
end
