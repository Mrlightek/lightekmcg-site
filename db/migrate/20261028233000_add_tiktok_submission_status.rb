class AddTiktokSubmissionStatus < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_marketing_social_posts, :submission_status, :string
    add_column :lightek_marketing_social_posts, :last_checked_at, :datetime
  end
end
