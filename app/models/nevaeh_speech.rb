class NevaehSpeech < ApplicationRecord
  belongs_to :user
  has_one_attached :audio
  validates :request_key,format:{with:/\A[a-zA-Z0-9_-]{8,100}\z/},uniqueness:{scope: :user_id}
  validates :status,inclusion:{in:%w[queued running ready failed cancelled]}
  validates :text,presence:true,length:{maximum:1800}
  validates :voice,inclusion:{in:%w[en-us+f3 en-gb+f3 ar+f3]}
  validates :speed,numericality:{only_integer:true,greater_than_or_equal_to:100,less_than_or_equal_to:220}
  validate do
    %w[user_id request_key fingerprint text voice speed].each do |field|
      errors.add(field,'is immutable') if persisted? && will_save_change_to_attribute?(field)
    end
  end
  # Reuse Studio's existing audio-envelope decoder without creating a Studio asset.
  def file = audio
end
