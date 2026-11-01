# frozen_string_literal: true
class AddNevaehReportingToInstallations < ActiveRecord::Migration[8.0]
  def change
    add_column :gatekeeper_installations, :nevaeh_reporting_secret_slug, :string
    add_column :gatekeeper_installations, :nevaeh_reporting_configured_at, :datetime
    add_column :gatekeeper_installations, :nevaeh_reporting_error, :text
  end
end
