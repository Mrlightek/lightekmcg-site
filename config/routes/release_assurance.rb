# frozen_string_literal: true

namespace :dashboard do
  resources :release_assurance, only: %i[index show create] do
    collection do
      post :register_tester
      post :offboard_tester
    end
    member do
      post :publish
      post :accept
      post :prepare
      post :deploy
      post :retire
      post :rollback
      post :recommend
      post :promote
      post :learn
      post :assign
      post :verify_feedback
      post :retest
      get "evidence/:run_id", action: :evidence, as: :evidence
    end
  end
end

get "/release-beta", to: "release_beta#show", as: :release_beta
post "/release-beta/redeem", to: "release_beta#redeem", as: :redeem_release_beta
post "/release-beta/launch", to: "release_beta#launch", as: :launch_release_beta
post "/release-beta/feedback", to: "release_beta#feedback", as: :feedback_release_beta
post "/release-beta/account", to: "release_beta#account"
post "/release-beta/account/revoke", to: "release_beta#revoke"
