namespace :dashboard do
  resources :remote_support_sessions, path: "it-support/screen-sharing", only: %i[index show create] do
    member do
      post :approve
      post :exchange
      post :offer_file
      post "files/:transfer_id/accept", action: :accept_file, as: :accept_file
      post "files/:transfer_id/cancel", action: :cancel_file, as: :cancel_file
      post "files/:transfer_id/download", action: :download_file, as: :download_file
      delete :end_session
    end
  end
end
