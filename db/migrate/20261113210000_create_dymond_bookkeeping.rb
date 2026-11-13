class CreateDymondBookkeeping < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_accounting_books do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :currency, null: false, default: 'USD'
      t.string :timezone, null: false, default: 'America/New_York'
      t.timestamps
    end
    create_table :lightek_accounting_bank_accounts do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.string :name, null: false
      t.date :opening_on, null: false
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
    create_table :lightek_accounting_categories do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.string :name, null: false
      t.string :kind, null: false
      t.string :schedule_code
      t.integer :deduction_bps, null: false, default: 10000
      t.timestamps
    end
    create_table :lightek_accounting_imports do |t|
      t.references :bank_account, null: false, foreign_key: {to_table: :lightek_accounting_bank_accounts}
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.string :status, null: false, default: 'preview'
      t.string :source_digest, null: false
      t.timestamps
    end
    create_table :lightek_accounting_reconciliations do |t|
      t.references :bank_account, null: false, foreign_key: {to_table: :lightek_accounting_bank_accounts}
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :status, null: false, default: 'draft'
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
    add_index :lightek_accounting_reconciliations, [:bank_account_id,:starts_on,:ends_on], unique: true, where: "status = 'final'", name: 'idx_accounting_final_period'
    create_table :lightek_accounting_transactions do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :bank_account, null: false, foreign_key: {to_table: :lightek_accounting_bank_accounts}
      t.references :category, foreign_key: {to_table: :lightek_accounting_categories}
      t.references :statement_import, foreign_key: {to_table: :lightek_accounting_imports}
      t.references :reconciliation, foreign_key: {to_table: :lightek_accounting_reconciliations}
      t.date :posted_on, null: false
      t.string :source_key, null: false
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
    add_index :lightek_accounting_transactions, [:book_id,:posted_on,:id], name: 'idx_accounting_book_date'
    add_index :lightek_accounting_transactions, [:bank_account_id,:posted_on], name: 'idx_accounting_account_date'
    add_index :lightek_accounting_transactions, [:bank_account_id,:reconciliation_id], name: 'idx_accounting_uncleared'
    add_index :lightek_accounting_transactions, [:bank_account_id,:source_key], unique: true, name: 'idx_accounting_source_key'
    create_table :lightek_accounting_rules do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :category, null: false, foreign_key: {to_table: :lightek_accounting_categories}
      t.integer :priority, null: false, default: 100
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
    create_table :lightek_accounting_workbooks do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
    create_table :lightek_accounting_audit_events do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :action, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :proof_digest
      t.timestamps
    end
    create_table :lightek_accounting_automations do |t|
      t.references :book, null: false, foreign_key: {to_table: :lightek_accounting_books}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.boolean :enabled, null: false, default: true
      t.datetime :next_run_at, null: false
      t.datetime :last_run_at
      t.string :error_code
      t.string :record_key, null: false
      t.jsonb :sealed_data, null: false
      t.timestamps
    end
  end
end
