Rails.application.config.to_prepare do
  if defined?(DymondSite::Page) && !DymondSite::Page.reflect_on_association(:growth_page_metadata)
    DymondSite::Page.has_one :growth_page_metadata, class_name: 'LightekGrowth::PageMetadata', foreign_key: :page_id, dependent: :destroy
  end
end
