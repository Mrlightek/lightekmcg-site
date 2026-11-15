class CreateNevaehSpeechSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_speech_segments do |t|
      t.references :nevaeh_speech,null:false,foreign_key:true
      t.integer :position,null:false
      t.text :text,null:false
      t.string :status,null:false,default:'queued'
      t.float :duration
      t.json :mouth_frames,null:false,default:[]
      t.timestamps
    end
    add_index :nevaeh_speech_segments,[:nevaeh_speech_id,:position],unique:true
  end
end
