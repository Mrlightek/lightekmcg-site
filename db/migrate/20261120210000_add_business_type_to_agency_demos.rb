class AddBusinessTypeToAgencyDemos < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_agency_trial_requests, :business_type, :string, default: 'general', null: false
    add_column :lightek_agency_trials, :business_type, :string, default: 'general', null: false
  end
end
