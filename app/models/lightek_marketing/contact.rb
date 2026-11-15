# frozen_string_literal: true
module LightekMarketing
  class Contact < ApplicationRecord
    self.table_name = "lightek_marketing_contacts"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :sales_account, class_name: "LightekSales::Account", optional: true
    belongs_to :sales_owner, class_name: "User", optional: true
    validates :name, :job_title, length: {maximum: 160}
    validates :phone, length: {maximum: 80}
    validates :sales_notes, length: {maximum: 20_000}
    validate do
      if persisted? && sales_account_id_changed? && LightekSales::Opportunity.where(contact_id: id).where.not(account_id: sales_account_id).exists?
        errors.add(:sales_account, "cannot change while this contact has deals with another company")
      end
      errors.add(:sales_account, "must belong to this website") if sales_account && sales_account.site_id != site_id
      if sales_owner_id.present? && (new_record? || sales_owner_id_changed?) && site && !LightekSales::Access.owners_for(site).exists?(id: sales_owner_id)
        errors.add(:sales_owner, "must be an owner or sales-enabled member of this website")
      end
    end
    validates :email, presence: true, uniqueness: {scope: :site_id}, format: {with: URI::MailTo::EMAIL_REGEXP}
    before_validation { self.email = email.to_s.strip.downcase }
    scope :subscribed, -> { where.not(subscribed_at: nil).where(unsubscribed_at: nil) }
  end
end
