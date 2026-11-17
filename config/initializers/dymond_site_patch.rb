# config/initializers/dymond_site_patch.rb
Rails.application.reloader.to_prepare do
  if defined?(DymondSite::Site)
    # db:create/db:migrate boot Rails before a new instance has its schema.
    # Re-evaluate on the next prepare/boot once the table is available.
    begin
      next unless DymondSite::Site.table_exists?
    rescue ActiveRecord::NoDatabaseError
      next
    end
    DymondSite::Site.class_eval do
      # Alias domain to host so engine queries using domain automatically query host
      alias_attribute :domain, :host unless column_names.include?("domain")
    end
  end
end
