class StudioWorkstation < ApplicationRecord
  belongs_to :owner,class_name:"User"
  belongs_to :site,class_name:"DymondSite::Site",optional:true
  belongs_to :studio_scene
  validates :session_key,format:{with:/\A[a-f0-9]{32}\z/},uniqueness:true
  validates :request_key,presence:true,uniqueness:{scope: :owner_id}
  validates :status,inclusion:{in:%w[starting building ready saving stopped failed expired]}
  def active? = %w[starting building ready saving].include?(status) && expires_at.future?
end
