class CreateLightekBlogEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_blog_entries do |t|
      t.references :site, null:false, foreign_key:{to_table: :dymond_site_sites}
      t.references :post, null:false, foreign_key:{to_table: :posts,on_delete: :cascade}, index:{unique:true}
      t.string :slug, null:false, limit:160
      t.string :status, null:false, default:"draft"
      t.text :excerpt
      t.string :category, limit:80
      t.datetime :published_at
      t.integer :lock_version, null:false, default:0
      t.timestamps
    end
    add_index :lightek_blog_entries, [:site_id,:slug], unique:true
    add_index :lightek_blog_entries, [:site_id,:status,:published_at],name:"idx_blog_publication_feed"
    add_check_constraint :lightek_blog_entries,"status IN ('draft','published','archived') AND (status <> 'published' OR published_at IS NOT NULL)",name:"blog_publication_state_valid"
  end
end
