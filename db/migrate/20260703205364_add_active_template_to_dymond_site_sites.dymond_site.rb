# frozen_string_literal: true
# This migration comes from dymond_site (originally 20260703204653)
class AddActiveTemplateToDymondSiteSites < ActiveRecord::Migration[8.0]
  def change
    add_reference :dymond_site_sites, :active_template,
                  foreign_key: { to_table: :dymond_site_site_templates }, null: true
  end
end
