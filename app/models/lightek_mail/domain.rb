module LightekMail
  class Domain < ApplicationRecord
    self.table_name = "lightek_mail_domains"
    belongs_to :user
    has_many :accounts, class_name: "LightekMail::Account", dependent: :restrict_with_error
    before_validation { self.name = name.to_s.strip.downcase; self.verification_token ||= SecureRandom.hex(24) }
    validates :name, uniqueness: true, format: {with: /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/}
    def verification_value = "lightek-mail=#{verification_token}"
  end
end
