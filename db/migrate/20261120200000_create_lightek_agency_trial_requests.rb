class CreateLightekAgencyTrialRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_agency_trial_requests do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.string :email_address, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :lightek_agency_trial_requests, [:site_id, :email_address, :created_at], name: :index_agency_trial_requests_on_site_and_email
  end
end
