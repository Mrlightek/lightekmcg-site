# frozen_string_literal: true

class AddSalesPartnerPayoutOnboarding < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_sales_partners, :payout_user, foreign_key: {to_table: :users}
    add_reference :lightek_sales_partners, :payout_invited_by, foreign_key: {to_table: :users}
    add_column :lightek_sales_partners, :payout_entity_type, :string
    add_column :lightek_sales_partners, :payout_setup_started_at, :datetime
  end
end
