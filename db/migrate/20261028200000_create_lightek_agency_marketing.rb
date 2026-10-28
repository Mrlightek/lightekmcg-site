class CreateLightekAgencyMarketing < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_agency_site_memberships do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "marketer"
      t.references :granted_by, null: false, foreign_key: {to_table: :users}
      t.timestamps
    end
    add_index :lightek_agency_site_memberships, [:site_id, :user_id], unique: true, name: "idx_agency_site_member"
    create_table :lightek_marketing_contacts do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :email, null: false
      t.datetime :subscribed_at
      t.datetime :unsubscribed_at
      t.string :consent_source
      t.timestamps
    end
    add_index :lightek_marketing_contacts, [:site_id, :email], unique: true
    create_table :lightek_marketing_deliveries do |t|
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :contact, null: false, foreign_key: {to_table: :lightek_marketing_contacts}
      t.references :mail_message, foreign_key: {to_table: :lightek_mail_messages}
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.timestamps
    end
    add_index :lightek_marketing_deliveries, [:campaign_id, :contact_id], unique: true
  end
end
