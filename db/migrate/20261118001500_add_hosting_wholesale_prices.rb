class AddHostingWholesalePrices < ActiveRecord::Migration[8.0]
  def change
    add_column :hosting_packages, :wholesale_price_cents, :integer
    add_column :hosting_packages, :reseller_minimum_margin_cents, :integer, null: false, default: 500
    add_check_constraint :hosting_packages, "wholesale_price_cents IS NULL OR wholesale_price_cents > 0", name: "hosting_wholesale_positive"
    add_check_constraint :hosting_packages, "reseller_minimum_margin_cents >= 0", name: "hosting_reseller_margin_nonnegative"
  end
end
