class CreatePwaPlatformOperators < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_platform_operators do |t|
      t.references :site, null: false, index: {unique: true}
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.timestamps
    end
  end
end
