module LightekBlog
  class Editor
    def self.save!(site:,user:,attributes:,entry:nil)
      LightekDesign::SiteTheme.authorize!(site,user)
      values=attributes.to_h.stringify_keys
      raise ActiveRecord::RecordNotFound if entry && entry.site_id!=site.id
      entry ||= Entry.new(site:site,post:Post.new(site:site,user:user,kind:"article",audience:"everyone",visibility:"private",moderation_state:"hidden"))
      Entry.transaction do
        entry.lock_version=Integer(values.fetch("lock_version")) if entry.persisted?
        entry.assign_attributes(slug:values["slug"].to_s.strip,excerpt:values["excerpt"],category:values["category"].to_s.strip,status:values.fetch("status","draft"))
        entry.published_at ||= Time.current if entry.status=="published"
        entry.post.assign_attributes(title:values["title"].to_s.strip,content:values["content"].to_s,
          visibility:entry.status=="published" ? "public" : "private",moderation_state:entry.status=="published" ? "published" : "hidden")
        raise ArgumentError,"Give your article a title and body." if entry.post.title.blank? || entry.post.content.blank?
        # Shared Post is the source for the website and PWA/community feed.
        entry.post.metadata=entry.post.metadata.to_h.merge("website_article"=>{"slug"=>entry.slug,"url"=>"/blog/#{entry.slug}"})
        entry.valid? # Validate before writing the shared post; keep form errors.
        raise ActiveRecord::RecordInvalid.new(entry) if entry.errors.any?
        entry.post.save!
        entry.save!
      end
      entry
    end
  end
end
