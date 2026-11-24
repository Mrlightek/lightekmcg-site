post "/webhooks/telnyx", to: "webhooks/telnyx#create"

scope "/dashboard" do
  resources :user_esims, controller: "dashboard/user_esims", only: %i[create show] do
    member do
      get :activation
      patch :top_up
      patch :set_status, path: "status"
    end
  end
end
