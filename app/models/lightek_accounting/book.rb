module LightekAccounting
  class Book < ApplicationRecord
    self.table_name = 'lightek_accounting_books'
    belongs_to :employer, class_name: 'User'
    has_many :bank_accounts, dependent: :restrict_with_exception
    has_many :transactions, dependent: :restrict_with_exception
    has_many :categories, dependent: :restrict_with_exception
    after_create { StarterChart.install!(self) }
    validates :name, presence: true, length: {maximum: 150}
    validates :currency, inclusion: {in: ['USD']}
    validates :timezone, inclusion: {in: ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }.uniq}
  end
end
