module LightekFeatureFlags
  class Change < ApplicationRecord
    self.table_name = "lightek_feature_flag_changes"
    belongs_to :flag, class_name: "LightekFeatureFlags::Flag"
    belongs_to :actor, class_name: "User"
    attr_readonly :flag_id, :actor_id, :previous, :current
  end
end
