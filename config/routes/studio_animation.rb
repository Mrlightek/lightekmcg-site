# frozen_string_literal: true

namespace :studio do
  namespace :animation do
    resources :assets, only: %i[index show create update destroy] do
      get :file, on: :member
      match :preview, via: %i[get post], on: :member
    end
    resources :scenes, only: %i[index show create update destroy] do
      resources :renders, only: %i[index show create destroy] do
        get :video, on: :member
      end
    end
  end
end
