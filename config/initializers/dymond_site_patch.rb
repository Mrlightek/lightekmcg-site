# config/initializers/dymond_site_patch.rb
Rails.application.reloader.to_prepare do
  if defined?(DymondSite::Site)
    DymondSite::Site.class_eval do
      # Alias domain to host so engine queries using domain automatically query host
      alias_attribute :domain, :host unless column_names.include?("domain")
    end
  end
end