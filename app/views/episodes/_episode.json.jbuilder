json.extract! episode, :id, :title, :subtitle, :url, :description, :show_title, :show_description, :created_at, :updated_at
json.url episode_url(episode, format: :json)
