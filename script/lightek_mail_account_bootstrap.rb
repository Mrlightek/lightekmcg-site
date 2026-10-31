# frozen_string_literal: true
# Run within the customer's isolated Rails installation after mailbox setup.
# Usage: LIGHTEK_INITIAL_MAIL_OWNER=... LIGHTEK_INITIAL_MAIL_ADDRESS=... bin/rails runner script/lightek_mail_account_bootstrap.rb
owner_email = ENV.fetch("LIGHTEK_INITIAL_MAIL_OWNER").strip.downcase
address = ENV.fetch("LIGHTEK_INITIAL_MAIL_ADDRESS").strip.downcase
raise ArgumentError, "Invalid mailbox" unless address.match?(/\A[a-z0-9][a-z0-9._+-]{0,63}@[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/)
raise ArgumentError, "Invalid owner" unless owner_email.match?(/\A[^\s@]+@[^\s@]+\z/)
owner = User.find_by!(email_address: owner_email)
domain_name = address.split("@", 2).last
LightekMail::Domain.transaction do
  domain = LightekMail::Domain.find_or_create_by!(name: domain_name) { |record| record.user = owner }
  raise "Mailbox domain belongs to another user" unless domain.user_id == owner.id
  account = LightekMail::Account.find_or_initialize_by(address: address)
  raise "Mailbox belongs to another user" if account.persisted? && account.user_id != owner.id
  account.user = owner
  account.domain = domain
  account.display_name = owner.first_name.presence || "Lightek Mail" if account.display_name.blank?
  account.enabled = false if account.new_record?
  account.save!
  puts "LIGHTEK_MAIL_ACCOUNT_REGISTERED=#{account.id}"
end
