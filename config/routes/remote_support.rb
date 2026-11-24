namespace :dashboard do
  resources :remote_support_sessions, path: "it-support/screen-sharing", only: %i[index show create] do
    member do
      post :approve
      post :exchange
      delete :end_session
    end
  end
end
