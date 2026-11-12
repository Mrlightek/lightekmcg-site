module LightekBlog
  class Entry < ApplicationRecord
    self.table_name="lightek_blog_entries"
    belongs_to :site,class_name:"DymondSite::Site"
    belongs_to :post
    validates :slug,format:{with:/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/},length:{maximum:160},uniqueness:{scope: :site_id}
    validates :status,inclusion:{in:%w[draft published archived]}
    validates :category,length:{maximum:80}
    validates :excerpt,length:{maximum:600}
    validates :published_at,presence:true,if:-> {status=="published"}
    validate :matching_post
    scope :publicly_visible,-> {joins(:post).where(status:"published",posts:{kind:"article",visibility:"public",moderation_state:"published",audience:"everyone"}).where("lightek_blog_entries.published_at <= ?",Time.current).merge(Post.unexpired)}
    def matching_post
      errors.add(:post,"must be a standalone article belonging to this website") if post && (post.site_id!=site_id || post.kind!="article" || post.parent_id || post.community_id)
    end
  end
end
