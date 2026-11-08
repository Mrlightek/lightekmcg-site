class CreateWebsiteTemplateInquiries < ActiveRecord::Migration[8.0]
  def change
    create_table :website_template_inquiries do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :template_key, null: false
      t.string :section_key, null: false
      t.jsonb :fields, null: false, default: {}
      t.timestamps
    end
  end
end
