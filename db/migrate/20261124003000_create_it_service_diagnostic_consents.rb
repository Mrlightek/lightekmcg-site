class CreateItServiceDiagnosticConsents < ActiveRecord::Migration[8.0]
  def change
    create_table :it_service_diagnostic_consents do |t|
      t.references :it_service_request, null: false, foreign_key: true, index: { unique: true }
      t.references :granted_by, null: false, foreign_key: { to_table: :users }
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
  end
end
