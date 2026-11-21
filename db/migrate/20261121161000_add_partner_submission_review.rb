class AddPartnerSubmissionReview < ActiveRecord::Migration[8.0]
  def change
    change_table :studio_program_distribution_handoffs do |t|
      t.string :spec_reference
      t.string :submission_reference
      t.datetime :submitted_at
      t.json :quality_checks
    end
  end
end
