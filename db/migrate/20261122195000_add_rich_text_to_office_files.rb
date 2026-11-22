class AddRichTextToOfficeFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_office_files, :rich_text, :boolean, null: false, default: false
    add_column :lightek_network_office_files, :rich_text, :boolean, null: false, default: false
  end
end
