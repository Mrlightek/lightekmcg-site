module LightekMail
  class Contact < ApplicationRecord
    self.table_name = "lightek_mail_contacts"

    belongs_to :account, class_name: "LightekMail::Account"

    EMAIL = /\A[^\s<>@,;]+@(?:[a-z0-9-]+\.)+[a-z]{2,63}\z/i

    def self.valid_email?(value)
      value.bytesize <= 254 && EMAIL.match?(value) && !value.match?(/[[:cntrl:]]/)
    end

    def self.for_mailbox(account)
      where(account_id: account.id)
    end

    def self.search(query)
      pattern = "%#{sanitize_sql_like(query.downcase)}%"
      where("LOWER(name) LIKE ? OR LOWER(CAST(emails AS TEXT)) LIKE ?", pattern, pattern)
    end

    def display_name
      name.presence || emails.first || phones.first
    end
  end
end
