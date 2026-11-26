# frozen_string_literal: true

class CreateAccountSetupSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :account_setup_settings do |t|
      t.integer :link_minutes, default: 2880, null: false
      t.timestamps
    end
  end
end
