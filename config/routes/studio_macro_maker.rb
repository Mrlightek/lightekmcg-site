scope "/api/v1/studio/macro_maker", module: "studio/macro_maker", format: false do
  get "catalog", to: "catalog#index"
  post "validate", to: "compositions#validate"
  get "compositions", to: "compositions#index"
  post "compositions", to: "compositions#create"
  get "compositions/:operation_id", to: "compositions#show", constraints: {operation_id: /[^\/]+/}
  get "operations/:id", to: "operations#show", constraints: {id: /[^\/]+/}
end

get "/studio/macro_maker", to: "studio/macro_maker/editor#index", as: :studio_macro_maker
scope "/studio/macro_maker", module: "studio/macro_maker", as: :studio_macro_maker, format: false do
  get "compositions/new", to: "editor#new", as: :new_composition
  get "compositions/:operation_id/edit", to: "editor#edit", as: :edit_composition,
    constraints: {operation_id: /[^\/]+/}
  post "compositions", to: "editor#create", as: :compositions
end

scope "/studio/macro_maker", module: "studio/macro_maker", as: :studio_macro_maker, format: false do
  get "compositions/:operation_id/run", to: "runs#new", as: :run,
    constraints: {operation_id: /[^\/]+/}
  post "compositions/:operation_id/run", to: "runs#create", constraints: {operation_id: /[^\/]+/}
  post "compositions/:operation_id/apply", to: "runs#apply", as: :apply,
    constraints: {operation_id: /[^\/]+/}
  get "editors/:editor", to: "editor_features#show", as: :engine_editor
  get "editors/:editor/features", to: "editor_features#index", as: :engine_features
  get "runs/:id/status", to: "runs#status", as: :run_status, constraints: {id: /\d+/}
  get "runs/:id/download", to: "runs#download", as: :download_run, constraints: {id: /\d+/}
end
