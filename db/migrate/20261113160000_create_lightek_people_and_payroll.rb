class CreateLightekPeopleAndPayroll < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_people_departments do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :parent, foreign_key: {to_table: :lightek_people_departments}
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :lightek_people_departments, [:employer_id, :code], unique: true
    create_table :lightek_people_employments do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :worker, null: false, foreign_key: {to_table: :users}
      t.references :department, foreign_key: {to_table: :lightek_people_departments}
      t.references :manager, foreign_key: {to_table: :lightek_people_employments}
      t.string :title, null: false
      t.string :level, null: false, default: 'individual_contributor'
      t.string :worker_kind, null: false, default: 'employee'
      t.boolean :active, null: false, default: true
      t.boolean :people_admin, null: false, default: false
      t.string :payroll_access, null: false, default: 'none'
      t.date :starts_on, null: false
      t.date :ends_on
      t.timestamps
    end
    add_index :lightek_people_employments, [:employer_id, :worker_id], unique: true, name: 'idx_people_employer_worker'
    create_table :lightek_people_benefit_plans do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :category, null: false
      t.string :currency, null: false, default: 'USD'
      t.string :deduction_treatment, null: false, default: 'post_tax'
      t.bigint :employee_cents, null: false, default: 0
      t.bigint :employer_cents, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.timestamps
    end
    create_table :lightek_people_benefit_enrollments do |t|
      t.references :employment, null: false, foreign_key: {to_table: :lightek_people_employments}
      t.references :benefit_plan, null: false, foreign_key: {to_table: :lightek_people_benefit_plans}
      t.date :starts_on, null: false
      t.date :ends_on
      t.timestamps
    end
    add_index :lightek_people_benefit_enrollments, [:employment_id, :benefit_plan_id], unique: true, where: 'ends_on IS NULL', name: 'idx_people_benefit_election'
    create_table :lightek_people_pay_runs do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :prepared_by, null: false, foreign_key: {to_table: :users}
      t.references :approved_by, foreign_key: {to_table: :users}
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :pay_date, null: false
      t.string :currency, null: false, default: 'USD'
      t.string :status, null: false, default: 'draft'
      t.string :financial_account_ref
      t.datetime :approved_at
      t.timestamps
    end
    add_index :lightek_people_pay_runs, [:employer_id, :period_start, :period_end, :pay_date], unique: true,
      where: "status <> 'canceled'", name: 'idx_people_pay_period'
    create_table :lightek_people_pay_statements do |t|
      t.references :pay_run, null: false, foreign_key: {to_table: :lightek_people_pay_runs}
      t.references :employment, null: false, foreign_key: {to_table: :lightek_people_employments}
      t.references :prepared_by, null: false, foreign_key: {to_table: :users}
      t.bigint :gross_cents, null: false
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :employer_tax_cents, null: false, default: 0
      t.bigint :other_deductions_cents, null: false, default: 0
      t.bigint :benefit_cents, null: false, default: 0
      t.bigint :employer_benefit_cents, null: false, default: 0
      t.bigint :net_cents, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.string :tax_reference, null: false
      t.string :status, null: false, default: 'draft'
      t.string :provider_ref
      t.string :provider_status
      t.datetime :attempted_at
      t.string :error_code
      t.jsonb :quote, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_people_pay_statements, [:pay_run_id, :employment_id], unique: true, name: 'idx_people_run_worker'
    add_index :lightek_people_pay_statements, :provider_ref, unique: true
    add_check_constraint :lightek_people_pay_statements, 'gross_cents >= 0 AND tax_cents >= 0 AND employer_tax_cents >= 0 AND other_deductions_cents >= 0 AND benefit_cents >= 0 AND employer_benefit_cents >= 0 AND net_cents >= 0', name: 'people_payroll_nonnegative'
    add_check_constraint :lightek_people_pay_statements, 'net_cents = gross_cents - tax_cents - other_deductions_cents - benefit_cents', name: 'people_payroll_net_matches'
    create_table :lightek_people_payout_senders do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.string :financial_account_ref, null: false, index: {unique: true}
      t.timestamps
    end
    create_table :lightek_people_payout_destinations do |t|
      t.references :employment, null: false, foreign_key: {to_table: :lightek_people_employments}, index: {unique: true}
      t.string :provider, null: false, default: 'stripe_global'
      t.string :recipient_ref
      t.string :capability_status
      t.timestamps
    end
    create_table :lightek_people_audit_events do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :action, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.timestamps
    end
  end
end
