class AddHostedProgramLicenseExchange < ActiveRecord::Migration[8.0]
  def change
    change_column_null :studio_program_licenses, :licensor_site_id, true
    add_column :studio_program_licenses, :federation_key, :string
    add_column :studio_program_licenses, :originator_name, :string
    add_column :studio_program_licenses, :creative_digest, :string
    add_reference :studio_program_licenses, :publisher_peer, foreign_key: { to_table: :lightek_reservation_peers }
    add_index :studio_program_licenses, :federation_key, unique: true
  end
end
