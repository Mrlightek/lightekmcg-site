module LightekIdentity
  class LoginAttempt < ApplicationRecord
    self.table_name = 'lightek_identity_login_attempts'
    belongs_to :connection
    belongs_to :user, optional: true
  end
end
