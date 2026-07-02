# frozen_string_literal: true
# This migration comes from dymond_compute (originally 20260629223235)
class CreateDymondComputeAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_compute_assets do |t|
      t.string  :filename
      t.string  :content_type
      t.bigint  :byte_size
      t.string  :kind      # image | video | audio | document | other
      t.string  :purpose   # assets | media | uploads | vr
      t.string  :alt_text  # accessibility / captions
      t.timestamps
    end
    add_index :dymond_compute_assets, :kind
    add_index :dymond_compute_assets, :purpose
  end
end
