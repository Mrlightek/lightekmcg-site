class AddMemberCountToSusuGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :susu_groups, :target_member_count, :integer, null: false, default: 2
  end
end
