class AddDistributionScopeToProgramLicenses < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_program_licenses, :territories, :json
    add_column :studio_program_licenses, :platforms, :json
    add_column :studio_program_licenses, :web_screening_key, :string
    add_index :studio_program_licenses, :web_screening_key, unique: true
    add_reference :studio_program_licenses, :rights_attested_by, foreign_key: { to_table: :users }
    add_column :studio_program_licenses, :rights_evidence_reference, :string

    create_table :studio_program_distribution_handoffs do |t|
      t.references :license, null: false, foreign_key: { to_table: :studio_program_licenses }
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.string :platform, null: false
      t.string :partner, null: false
      t.json :territories, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :commercial, default: false, null: false
      t.timestamps
    end
  end
end
