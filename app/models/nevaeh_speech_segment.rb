class NevaehSpeechSegment < ApplicationRecord
  belongs_to :nevaeh_speech
  has_one_attached :audio
  has_one_attached :stream
  validates :position,numericality:{only_integer:true,greater_than_or_equal_to:0,less_than:12},uniqueness:{scope: :nevaeh_speech_id}
  validates :text,presence:true,length:{maximum:240}
  validates :status,inclusion:{in:%w[queued running ready]}
  # Mouth timing is measured from the encoded audio the playlist actually plays.
  def file = stream
end
