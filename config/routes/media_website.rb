constraints host: /\A(?:www\.)?lightekmcg\.com\z/i do
  get "/media", to: "media_website#index", as: :media_website, format: false
  get "/media/:page", to: "media_website#show", as: :media_website_page,
    constraints: { page: /[a-z-]+/ }, format: false
end
