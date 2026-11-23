require "tmpdir"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "minitest/autorun"
require "minitest/mock"
require "mail"
require "rack/test"

ROOT = File.expand_path("../..", __dir__)
TEMP_ROOT = Dir.mktmpdir("lightek-mail-import")
Minitest.after_run { FileUtils.rm_rf(TEMP_ROOT) }
ENV["DATABASE_URL"] = "sqlite3::memory:"

class MailboxImportTestApp < Rails::Application
  config.root = TEMP_ROOT
  config.eager_load = false
  config.active_support.to_time_preserves_timezone = :zone
  config.secret_key_base = "mail-import-test-" * 10
  config.logger = Logger.new(File::NULL)
  config.hosts.clear
  config.active_storage.service = :test
  config.active_storage.service_configurations = {test: {service: "Disk", root: File.join(TEMP_ROOT, "storage")}}
  config.active_job.queue_adapter = :test
end

Rails.application.initialize!
ActiveRecord::Schema.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.alias_method(:jsonb, :json)
ActiveRecord::Schema.define do
  create_table(:users) { |table| table.string :role, default: "client"; table.datetime :access_suspended_at }
  create_table(:lightek_test_employments) do |table|
    table.references :employer
    table.references :worker
    table.boolean :active, default: true
  end
end
require File.join(ROOT, "db/migrate/20261026150000_create_lightek_mail_studio")
require File.join(ROOT, "db/migrate/20261123145000_add_mailbox_imports")
CreateLightekMailStudio.new.migrate(:up)
AddMailboxImports.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261123151000_add_team_mail_migrations")
AddTeamMailMigrations.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261123153000_add_mail_contacts")
AddMailContacts.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261123102000_store_incoming_calendar_invitations")
StoreIncomingCalendarInvitations.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261123155000_add_calendar_history_imports")
AddCalendarHistoryImports.new.migrate(:up)
ActiveRecord::Schema.define do
  add_column :lightek_mail_messages, :junk, :boolean, default: false, null: false
  create_table(:active_storage_blobs) do |table|
    table.string :key, null: false
    table.string :filename, null: false
    table.string :content_type
    table.text :metadata
    table.string :service_name, null: false
    table.bigint :byte_size, null: false
    table.string :checksum
    table.datetime :created_at, null: false
  end
  create_table(:active_storage_attachments) do |table|
    table.string :name, null: false
    table.references :record, null: false, polymorphic: true
    table.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}
    table.datetime :created_at, null: false
  end
end

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class User < ApplicationRecord
  def can_access_feature?(feature) = feature == "mail"
end
module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    belongs_to :user
    has_many :messages, class_name: "LightekMail::Message"
    scope :mailboxes, -> { all }
  end
end
module LightekPeople
  class Employment < ApplicationRecord
    self.table_name = "lightek_test_employments"
    belongs_to :employer, class_name: "User"
    belongs_to :worker, class_name: "User"
    scope :active, -> { where(active: true) }
    def active_on?(_date) = active?
  end
  module LifecycleAccess
    def self.active?(user) = user.access_suspended_at.nil?
  end
end
module Dashboard; end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    helper_method :current_user
    def current_user = User.find(request.headers.fetch("X-Test-User"))
  end
end

%w[models/lightek_mail/message models/lightek_mail/mailbox_import services/lightek_mail/access
   services/lightek_mail/inbound services/lightek_mail/conversation services/lightek_mail/template_renderer
   services/lightek_mail/search services/lightek_mail/mbox_reader services/lightek_mail/mbox_message
   services/lightek_mail/mailbox_import_runner jobs/application_job jobs/lightek_mail/mailbox_import_job
   services/lightek_people/access services/lightek_team/workspace models/lightek_mail/team_migration
   models/lightek_mail/team_migration_mailbox services/lightek_mail/team_migration_mapping
   models/lightek_mail/contact models/lightek_mail/contact_preview services/lightek_mail/contact_import
   controllers/dashboard/mailbox_imports_controller controllers/dashboard/team_mail_migrations_controller
   models/lightek_mail/calendar_invitation models/lightek_mail/calendar_history_event
   models/lightek_mail/calendar_history_preview services/lightek_mail/calendar_notice
   services/lightek_mail/calendar_history_parser services/lightek_mail/calendar_history services/lightek_mail/submission
   controllers/dashboard/mail_contacts_controller controllers/dashboard/mail_calendar_imports_controller
   controllers/dashboard/mail_studio_controller].each { |path| require File.join(ROOT, "app", path) }

module MailboxImportFixtures
  def mailbox(user, address)
    domain_id = ActiveRecord::Base.connection.execute(
      "INSERT INTO lightek_mail_domains (user_id, name, verification_token, created_at, updated_at) VALUES " \
      "(#{user.id}, 'example.net-#{user.id}', 'test', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id"
    ).first.fetch("id")
    LightekMail::Account.create!(user: user, address: address, domain_id: domain_id, display_name: address)
  end

  def upload(contents)
    Rack::Test::UploadedFile.new(StringIO.new(contents), "application/mbox", true, original_filename: "Gmail.mbox")
  end

  def archive
    <<~MBOX
      From sender@example.org Fri Jun 12 12:00:00 +0000 2020
      From: Sender <sender@example.org>
      To: owner@example.net
      Date: Fri, 12 Jun 2020 12:00:00 +0000
      Message-ID: <receipt@example.org>
      X-Gmail-Labels: Inbox,Unread,Starred,Client receipts
      Subject: A historical receipt
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="receipt"

      --receipt
      Content-Type: text/plain; charset=UTF-8

      Here is your receipt.
      >From an escaped body line
      --receipt
      Content-Type: text/plain; name="receipt.txt"
      Content-Disposition: attachment; filename="receipt.txt"
      Content-Transfer-Encoding: base64

      UmVjZWlwdCBwcm9vZg==
      --receipt--

      From owner@example.net Sat Jun 13 10:00:00 +0000 2020
      From: Owner <owner@example.net>
      To: sender@example.org
      Date: Sat, 13 Jun 2020 10:00:00 +0000
      Message-ID: <reply@example.net>
      References: <receipt@example.org>
      X-Gmail-Labels: Sent,Client receipts
      Subject: Re: A historical receipt

      Thank you for the receipt.

      From broken@example.org Sun Jun 14 10:00:00 +0000 2020
      No headers
    MBOX
  end
end

class MailboxImportChecks < ActionController::TestCase
  tests Dashboard::MailboxImportsController
  include MailboxImportFixtures

  def setup
    @owner = User.create!
    @other_user = User.create!
    @account = mailbox(@owner, "owner-#{@owner.id}@example.net")
    @other_account = mailbox(@other_user, "other-#{@other_user.id}@example.net")
    @request.set_header("HTTP_X_TEST_USER", @owner.id.to_s)
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw do
      get "/mail/:account_id/calendar/import", to: "dashboard/mail_calendar_imports#index", as: :dashboard_mail_calendar_import
      get "/mail/:account_id/contacts", to: "dashboard/mail_contacts#index", as: :dashboard_mail_contacts
      get "/team/migrations", to: "dashboard/team_mail_migrations#index", as: :dashboard_team_mail_migrations
      get "/mail", to: "dashboard/mail_studio#index", as: :dashboard_mail
      scope "/mail/:account_id", controller: "dashboard/mailbox_imports" do
        get "/imports", action: :index, as: :dashboard_mailbox_imports
        post "/imports", action: :create
        get "/imports/:id", action: :show, as: :dashboard_mailbox_import
        post "/imports/:id/start", action: :start, as: :start_dashboard_mailbox_import
        post "/imports/:id/retry", action: :retry_import, as: :retry_dashboard_mailbox_import
        delete "/imports/:id", action: :destroy
      end
    end
    @routes = routes
    @controller.extend(routes.url_helpers)
    Dashboard::MailboxImportsController.prepend_view_path(File.join(ROOT, "app/views"))
    Dashboard::MailboxImportsController.helper_method(:dashboard_mail_path, :dashboard_mailbox_imports_path,
      :dashboard_mailbox_import_path, :start_dashboard_mailbox_import_path, :retry_dashboard_mailbox_import_path,
      :dashboard_team_mail_migrations_path, :dashboard_mail_contacts_path, :dashboard_mail_calendar_import_path)
  end

  def test_preview_import_thread_attachment_search_and_rerun
    get :index, params: {account_id: @account.id}
    assert_response :success
    assert_includes response.body, "Destination mailbox"
    refute_includes response.body, @other_account.address

    import = upload_archive(archive)
    assert_equal "queued", import.state
    perform(import)
    assert_equal "ready", import.state
    assert_equal 3, import.preview.fetch("messages")
    assert_equal 1, import.preview.fetch("invalid")
    assert_equal 0, @account.messages.count

    get :show, params: {account_id: @account.id, id: import.id}
    assert_response :success
    assert_includes response.body, "3 checked"
    assert_includes response.body, "Import into #{@account.address}"

    post :start, params: {account_id: @account.id, id: import.id}
    assert_response :see_other
    perform(import)
    assert_equal "complete", import.state
    assert_equal 2, import.results.fetch("imported")
    assert_equal 1, import.results.fetch("invalid")
    first, reply = @account.messages.order(:created_at).to_a
    assert_equal Time.utc(2020, 6, 12, 12), first.created_at
    assert_nil first.read_at
    assert first.starred?
    assert_includes first.imported_labels, "Client receipts"
    assert_includes first.text_body, "From an escaped body line"
    assert_equal "receipt.txt", first.attachments.first.filename.to_s
    assert_equal "Receipt proof", first.attachments.first.download
    assert_includes first.source.download, "X-Gmail-Labels:"
    assert_equal [first, reply], LightekMail::Conversation.messages(@account, reply)
    assert_equal [first, reply], LightekMail::Search.apply(@account.messages, 'label:"Client receipts"').order(:created_at).to_a
    assert_empty LightekMail::Search.apply(@account.messages, "label:Client")
    assert_equal "sent", reply.state
    assert_equal "outbound", reply.direction
    assert_nil reply.submitted_at

    import.start_import!
    perform(import)
    assert_equal 2, import.results.fetch("skipped")
    assert_equal 2, @account.messages.count
    assert_nil import.results["imported"]

    delete :destroy, params: {account_id: @account.id, id: import.id}
    assert_response :see_other
    assert_empty LightekMail::MailboxImport.in_mailbox(@account)
    assert_equal 2, @account.messages.count
    assert_equal "Receipt proof", first.attachments.first.download
  end

  def test_quota_failure_resumes_at_saved_offset_and_skips_stale_job
    import = upload_archive(archive)
    perform(import)
    first_entry = nil
    LightekMail::MboxReader.each(StringIO.new(archive)) { |entry| first_entry ||= entry }
    first_message = LightekMail::MboxMessage.new(first_entry)
    @account.update!(storage_limit: first_message.attributes.fetch(:bytesize))
    import.start_import!
    original_token = import.run_token
    perform(import)
    assert_equal "failed", import.state
    assert_equal first_entry.next_offset, import.byte_offset
    assert_match(/storage is full/, import.error_message)
    assert_equal 1, @account.messages.count

    @account.update!(storage_limit: 1.megabyte)
    import.retry!
    LightekMail::MailboxImportJob.perform_now(import.id, original_token)
    assert_equal "queued", import.reload.state
    perform(import)
    assert_equal "complete", import.state
    assert_equal 2, import.results.fetch("imported")
    assert_equal 2, @account.messages.count
  end

  def test_attachment_upload_failure_leaves_the_message_and_checkpoint_uncommitted
    import = upload_archive(archive)
    perform(import)
    import.start_import!
    service = import.archive.blob.service
    storage_upload = service.method(:upload)
    failures = 0
    failing_upload = lambda do |key, io, **options|
      if options[:checksum] == Base64.strict_encode64(Digest::MD5.digest("Receipt proof"))
        failures += 1
        raise IOError, "test storage failure"
      end
      storage_upload.call(key, io, **options)
    end
    blob_ids = ActiveStorage::Blob.pluck(:id)
    service.stub(:upload, failing_upload) { perform(import) }
    assert_equal 1, failures
    assert_equal "failed", import.state
    assert_equal 0, import.byte_offset
    assert_equal blob_ids, ActiveStorage::Blob.pluck(:id)
    assert_empty @account.messages

    import.retry!
    perform(import)
    assert_equal "complete", import.state
    assert_equal 2, @account.messages.count
  end

  def test_other_mailbox_is_inaccessible_and_invalid_archive_never_imports
    post :create, params: {account_id: @account.id, destination_account_id: @other_account.id, archive: upload(archive)}
    assert_response :not_found
    @request.set_header("CONTENT_TYPE", "application/x-www-form-urlencoded")
    import = upload_archive("this is not an MBOX")
    get :show, params: {account_id: @other_account.id, id: import.id}
    assert_response :not_found
    perform(import)
    assert_equal "failed", import.state
    assert_match(/does not start/, import.error_message)
    assert_raises(ArgumentError) { import.start_import! }
    assert_empty @account.messages
  end

  def test_existing_mail_and_label_only_reexport_are_deduplicated
    original = @account.messages.create!(message_id: "receipt@example.org", direction: "inbound", state: "inbox",
      from_address: "sender@example.org", subject: "Existing message")
    import = upload_archive(archive)
    perform(import)
    assert_equal 1, import.preview.fetch("skipped")
    import.start_import!
    perform(import)
    assert_equal 1, import.results.fetch("skipped")
    assert_equal "Existing message", original.reload.subject

    source = "Date: Fri, 12 Jun 2020 12:00:00 +0000\r\nX-Gmail-Labels: Label A\r\nSubject: Same bytes\r\n\r\nBody\r\n"
    from_line = "Fri Jun 12 12:00:00 +0000 2020"
    one, two = [source, source.sub("Label A", "Label B")].map do |raw|
      entry = LightekMail::MboxReader::Entry.new(raw: raw, envelope_date: from_line)
      LightekMail::MboxMessage.new(entry)
    end
    assert_equal one.idempotency_key, two.idempotency_key
  end

  private


  def upload_archive(contents)
    file = upload(contents)
    post :create, params: {account_id: @account.id, destination_account_id: @account.id, archive: file}
    assert_response :see_other
    assert_nil flash[:alert], flash[:alert]
    LightekMail::MailboxImport.in_mailbox(@account).order(:id).last!
  ensure
    @request.set_header("CONTENT_TYPE", "application/x-www-form-urlencoded")
  end

  def perform(import)
    import.reload
    LightekMail::MailboxImportJob.perform_now(import.id, import.run_token)
    import.reload
  end


end

MailboxImportTestApp.routes.draw do
  get "/mail", to: "dashboard/mail_studio#index", as: :dashboard_mail
  scope "/mail/accounts/:account_id", controller: "dashboard/mailbox_imports" do
    get "/imports", action: :index, as: :dashboard_mailbox_imports
    get "/imports/:id", action: :show, as: :dashboard_mailbox_import
    post "/imports/:id/approve", action: :approve, as: :approve_dashboard_mailbox_import
    post "/imports/:id/start", action: :start, as: :start_dashboard_mailbox_import
    post "/imports/:id/retry", action: :retry_import, as: :retry_dashboard_mailbox_import
    delete "/imports/:id", action: :destroy
  end

  get "/mail/accounts/:account_id/calendar", to: "dashboard/mail_studio#calendar", as: :calendar_dashboard_mail
  scope "/mail/accounts/:account_id/calendar/import", controller: "dashboard/mail_calendar_imports" do
    get "/", action: :index, as: :dashboard_mail_calendar_import
    post "/preview", action: :preview, as: :dashboard_mail_calendar_preview
    get "/preview/:id", action: :review, as: :dashboard_mail_calendar_review
    post "/preview/:id", action: :import
  end

  scope "/mail/accounts/:account_id/contacts", controller: "dashboard/mail_contacts" do
    get "/", action: :index, as: :dashboard_mail_contacts
    post "/preview", action: :preview, as: :dashboard_mail_contacts_preview
    get "/preview/:id", action: :review, as: :dashboard_mail_contacts_review
    post "/preview/:id", action: :import
    get "/suggestions", action: :suggestions, as: :dashboard_mail_contact_suggestions
    get "/:id/edit", action: :edit, as: :edit_dashboard_mail_contact
    patch "/:id", action: :update, as: :dashboard_mail_contact
  end

  resources :dashboard_team_mail_migrations, path: "/mail/team-migrations",
    controller: "dashboard/team_mail_migrations", only: %i[index create show] do
    post :start_ready, on: :member
    post "mailboxes/:mailbox_id/archive", action: :upload_archive, as: :upload_archive, on: :member
    post "mailboxes/:mailbox_id/archive/retry", action: :retry_archive, as: :retry_archive, on: :member
    delete "mailboxes/:mailbox_id/archive", action: :remove_archive, as: :remove_archive, on: :member
  end
end

class TeamMailMigrationChecks < ActionDispatch::IntegrationTest
  include MailboxImportFixtures

  def setup
    @owner = User.create!
    @member = User.create!(role: "employee")
    @second_member = User.create!(role: "employee")
    @outsider = User.create!
    @accounts = [@owner, @member, @second_member, @outsider].map { |user| mailbox(user, "person-#{user.id}@example.net") }
    [@member, @second_member].each do |member|
      LightekPeople::Employment.create!(employer_id: @owner.id, worker_id: member.id)
    end
    Dashboard::TeamMailMigrationsController.prepend_view_path(File.join(ROOT, "app/views"))
    Dashboard::MailboxImportsController.prepend_view_path(File.join(ROOT, "app/views"))
  end

  def test_three_people_migrate_and_retry_one_failed_mailbox
    get dashboard_team_mail_migrations_path, headers: as(@owner)
    assert_response :success
    assert_includes response.body, "source_email,destination_email"

    migration = create_migration(@accounts.first(3))
    get dashboard_team_mail_migration_path(migration), headers: as(@owner)
    assert_response :success
    assert_includes response.body, "3 mailboxes"
    assert_includes response.body, "Upload archive"
    owner_row, first_row, second_row = migration.mailboxes.order(:id).to_a
    [owner_row, first_row, second_row].each do |row|
      post upload_archive_dashboard_team_mail_migration_path(migration, mailbox_id: row.id),
        params: {archive: upload(archive)}, headers: as(@owner)
      assert_response :see_other
    end

    owner_import = owner_row.reload.mailbox_import
    first = first_row.reload.mailbox_import
    second = second_row.reload.mailbox_import
    assert_equal "queued", owner_import.state
    assert_equal "awaiting_approval", first.state
    perform(first)
    assert_empty first.preview
    post approve_dashboard_mailbox_import_path(first, account_id: first.account_id), headers: as(@owner)
    assert_response :not_found

    [first, second].each do |import|
      get dashboard_mailbox_import_path(import, account_id: import.account_id), headers: as(import.account.user)
      assert_response :success
      assert_includes response.body, "Approve archive"
      assert_includes response.body, "Old mail"
      post approve_dashboard_mailbox_import_path(import, account_id: import.account_id), headers: as(import.account.user)
      assert_response :see_other
      assert import.reload.approved_at?
    end
    [owner_import, first, second].each { |import| perform(import) }
    assert_equal ["ready"] * 3, [owner_import, first, second].map(&:state)
    first.account.update!(storage_limit: 1)
    post start_ready_dashboard_team_mail_migration_path(migration), headers: as(@owner)
    assert_response :see_other
    [owner_import, first, second].each { |import| perform(import) }
    assert_equal %w[complete failed complete], [owner_import, first, second].map(&:state)

    get dashboard_team_mail_migration_path(migration), headers: as(@owner)
    assert_response :success
    assert_includes response.body, "Retry this mailbox"
    assert_includes response.body, "2 complete"
    refute_includes response.body, "A historical receipt"

    first.account.update!(storage_limit: 1.megabyte)
    tokens = [owner_import.run_token, second.run_token]
    post retry_archive_dashboard_team_mail_migration_path(migration, mailbox_id: first_row.id), headers: as(@owner)
    assert_response :see_other
    perform(first)
    assert_equal "complete", first.state
    assert_equal tokens, [owner_import.reload.run_token, second.reload.run_token]
    @accounts.first(3).each do |account|
      messages = account.messages.order(:created_at).to_a
      assert_equal 2, messages.size
      assert_equal messages, LightekMail::Conversation.messages(account, messages.last)
      assert_equal "Receipt proof", messages.first.attachments.first.download
      assert_includes LightekMail::Access.accounts(account.user).pluck(:id), account.id
    end
  end

  def test_rejects_outside_mailboxes_and_rechecks_membership_after_approval
    assert_no_difference -> { LightekMail::TeamMigration.count } do
      create_migration_request([@accounts.first, @accounts.last], as(@owner))
      assert_response :see_other
      assert_equal dashboard_team_mail_migrations_path, URI.parse(response.location).path
    end

    migration = create_migration([@accounts.second])
    get dashboard_team_mail_migration_path(migration), headers: as(@outsider)
    assert_response :not_found
    get dashboard_team_mail_migration_path(migration), headers: as(@member)
    assert_response :forbidden
    row = migration.mailboxes.first
    post upload_archive_dashboard_team_mail_migration_path(migration, mailbox_id: row.id),
      params: {archive: upload(archive)}, headers: as(@owner)
    import = row.mailbox_import
    post approve_dashboard_mailbox_import_path(import, account_id: import.account_id), headers: as(@member)
    assert_response :see_other
    LightekPeople::Employment.find_by!(worker_id: @member.id, employer_id: @owner.id).update!(active: false)
    perform(import)
    assert_equal "failed", import.state
    assert_empty import.account.messages
    assert_empty import.preview
  end

  private

  def create_migration(accounts)
    create_migration_request(accounts, as(@owner))
    assert_response :see_other
    LightekMail::TeamMigration.where(employer: @owner).order(:id).last!
  end

  def create_migration_request(accounts, headers)
    csv = (["source_email,destination_email"] + accounts.map { |account| "old-#{account.id}@example.org,#{account.address}" }).join("\n")
    mapping = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", true, original_filename: "migration.csv")
    post dashboard_team_mail_migrations_path, params: {name: "Old mail", mapping: mapping}, headers: headers
  end

  def perform(import)
    LightekMail::MailboxImportJob.perform_now(import.id, import.reload.run_token)
    import.reload
  end

  def as(user)
    {"X-Test-User" => user.id.to_s}
  end
end

class MailContactsImportChecks < ActionDispatch::IntegrationTest
  include MailboxImportFixtures

  def setup
    @workspace_owner = User.create!
    @member = User.create!(role: "employee")
    @account = mailbox(@member, "contacts-#{@member.id}@lightek.example.net")
    LightekPeople::Employment.create!(employer_id: @workspace_owner.id, worker_id: @member.id)
    @migration = LightekMail::TeamMigration.create!(employer: @workspace_owner, name: "Move the team")
    @row = @migration.mailboxes.create!(account: @account, mailbox_user: @member,
      source_address: "old@example.org", destination_address: @account.address)
    Dashboard::MailContactsController.prepend_view_path(File.join(ROOT, "app/views"))
    Dashboard::TeamMailMigrationsController.prepend_view_path(File.join(ROOT, "app/views"))
  end

  def test_preview_import_edit_repeat_and_private_compose_suggestions
    get dashboard_mail_contacts_path(account_id: @account.id, team_mailbox_id: @row.id), headers: as(@member)
    assert_response :success
    assert_includes response.body, "Move the team"
    preview = upload_contacts
    assert_nil @row.reload.contacts_imported_at
    assert_empty LightekMail::Contact.for_mailbox(@account)
    get dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
    assert_response :success
    assert_includes response.body, "2 new · 1 duplicates · 1 unreadable"
    assert_includes response.body, "Client East"
    assert_includes response.body, "Harper"
    get dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), headers: as(@workspace_owner)
    assert_response :not_found

    apply_preview(preview)
    assert @row.reload.contacts_imported_at?
    book = LightekMail::Contact.for_mailbox(@account)
    assert_equal 2, book.count
    contact = book.find_by!(name: "Harper Lane")
    assert_equal ["sales@example.org", "other@example.org"], contact.emails
    assert_equal ["+1 202 555 0112"], contact.phones
    assert_equal ["Client East", "Team"], contact.labels

    get dashboard_mail_contact_suggestions_path(account_id: @account.id, q: "harper"), headers: as(@member)
    assert_response :success
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    assert_equal ["sales@example.org", "other@example.org"], JSON.parse(response.body).map { |row| row.fetch("email") }
    get dashboard_mail_contact_suggestions_path(account_id: @account.id, q: "harper"), headers: as(@workspace_owner)
    assert_response :not_found

    get edit_dashboard_mail_contact_path(account_id: @account.id, id: contact.id), headers: as(@member)
    assert_response :success
    assert_includes response.body, "Email addresses"
    patch dashboard_mail_contact_path(account_id: @account.id, id: contact.id),
      params: {contact: {name: "H. Lane", emails: "new@example.org", labels: "Updated"}}, headers: as(@member)
    assert_response :see_other

    duplicate_preview = upload_contacts
    get dashboard_mail_contacts_review_path(account_id: @account.id, id: duplicate_preview.id), headers: as(@member)
    assert_includes response.body, "0 new · 3 duplicates · 1 unreadable"
    apply_preview(duplicate_preview)
    assert_equal 2, book.count
    assert_equal "H. Lane", contact.reload.name
    assert_equal ["new@example.org"], contact.emails
    assert_equal ["Updated"], contact.labels

    get dashboard_team_mail_migration_path(@migration), headers: as(@workspace_owner)
    assert_response :success
    assert_includes response.body, "Contacts · Imported"
    refute_includes response.body, "new@example.org"
  end

  def test_expired_and_offboarded_team_import_cannot_apply
    preview = upload_contacts
    preview.update!(expires_at: 1.second.ago)
    post dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
    assert_response :not_found
    preview = upload_contacts
    LightekPeople::Employment.find_by!(worker_id: @member.id, employer_id: @workspace_owner.id).update!(active: false)
    post dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
    assert_response :forbidden
    assert_empty LightekMail::Contact.for_mailbox(@account)
    assert_nil @row.reload.contacts_imported_at
  end

  private

  def upload_contacts
    csv = <<~CSV
      First Name,Last Name,E-mail 1 - Value,E-mail 2 - Value,Phone 1 - Value,Labels
      Harper,Lane,sales@example.org,other@example.org,+1 202 555 0112,Client East ::: Team
      Alternate,Copy,OTHER@example.org,,,
      Sam,Phone,,,202-555-0400,Friends
      Invalid,Contact,not-an-address,,,
    CSV
    upload = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", true, original_filename: "contacts.csv")
    post dashboard_mail_contacts_preview_path(account_id: @account.id),
      params: {contacts_csv: upload, team_mailbox_id: @row.id}, headers: as(@member)
    assert_response :see_other
    LightekMail::ContactPreview.where(account: @account).sole
  end

  def apply_preview(preview)
    post dashboard_mail_contacts_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
    assert_response :see_other
    refute LightekMail::ContactPreview.exists?(preview.id)
  end

  def as(user)
    {"X-Test-User" => user.id.to_s}
  end
end

class MailCalendarHistoryChecks < ActionDispatch::IntegrationTest
  include MailboxImportFixtures

  def setup
    @owner = User.create!
    @member = User.create!(role: "employee")
    @account = mailbox(@member, "calendar-#{@member.id}@example.net")
    LightekPeople::Employment.create!(employer_id: @owner.id, worker_id: @member.id)
    migration = LightekMail::TeamMigration.create!(employer: @owner, name: "Move the team")
    @row = migration.mailboxes.create!(account: @account, mailbox_user: @member, source_address: "old@example.org",
      destination_address: @account.address)
    Dashboard::MailCalendarImportsController.prepend_view_path(File.join(ROOT, "app/views"))
    Dashboard::MailStudioController.prepend_view_path(File.join(ROOT, "app/views"))
  end

  def test_import_series_all_day_and_moved_occurrence_without_sending_mail
    Time.use_zone("America/New_York") do
      preview = upload_calendar
      assert_nil @row.reload.calendar_imported_at
      get dashboard_mail_calendar_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
      assert_response :success
      assert_includes response.body, "4 new · 0 duplicates · 1 need attention"
      assert_includes response.body, "Series exception"
      get dashboard_mail_calendar_review_path(account_id: @account.id, id: preview.id), headers: as(@owner)
      assert_response :not_found

      mail_count = @account.messages.count
      queued = ActiveJob::Base.queue_adapter.enqueued_jobs.size
      apply_preview(preview)
      assert @row.reload.calendar_imported_at?
      assert_equal 4, LightekMail::CalendarHistoryEvent.for_mailbox(@account).count

      first_week = LightekMail::CalendarHistory.week(@account, Date.new(2026, 10, 26))
      assert_equal [Time.utc(2026, 10, 29, 14)], first_week.map { |occurrence| occurrence.starts_at.utc }
      second_week = LightekMail::CalendarHistory.week(@account, Date.new(2026, 11, 2))
      assert_equal ["Moved planning", "Away"], second_week.map { |occurrence| occurrence.event.title }
      assert_equal Time.utc(2026, 11, 6, 16, 15), second_week.first.starts_at.utc
      assert_equal Time.utc(2026, 11, 7), second_week.last.starts_at.utc
      assert_equal Time.utc(2026, 11, 9), second_week.last.ends_at.utc
      third_week = LightekMail::CalendarHistory.week(@account, Date.new(2026, 11, 9))
      assert_equal [Time.utc(2026, 11, 15, 15)], third_week.map { |occurrence| occurrence.starts_at.utc }
      assert_empty LightekMail::CalendarHistory.week(@account, Date.new(2026, 11, 16))
      fourth_week = LightekMail::CalendarHistory.week(@account, Date.new(2026, 11, 23))
      assert_equal [Time.utc(2026, 11, 26, 15)], fourth_week.map { |occurrence| occurrence.starts_at.utc }

      get calendar_dashboard_mail_path(account_id: @account.id, date: "2026-11-02"), headers: as(@member)
      assert_response :success
      assert_includes response.body, "Moved planning"
      assert_includes response.body, "All day"
      refute_includes response.body, ">Weekly planning<"

      repeated = upload_calendar
      get dashboard_mail_calendar_review_path(account_id: @account.id, id: repeated.id), headers: as(@member)
      assert_includes response.body, "0 new · 4 duplicates"
      apply_preview(repeated)
      assert_equal 4, LightekMail::CalendarHistoryEvent.for_mailbox(@account).count
      assert_equal mail_count, @account.messages.count
      assert_equal queued, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    end
  end

  private

  def upload_calendar
    data = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:weekly@example.org
      SUMMARY:Weekly planning
      DTSTART;TZID=America/New_York:20261029T100000
      DTEND;TZID=America/New_York:20261029T103000
      RRULE:FREQ=WEEKLY;COUNT=5
      EXDATE;TZID=America/New_York:20261112T100000
      RDATE;TZID=America/New_York:20261115T100000
      END:VEVENT
      BEGIN:VEVENT
      UID:weekly@example.org
      RECURRENCE-ID;TZID=America/New_York:20261105T100000
      SUMMARY:Moved planning
      DTSTART;TZID=America/New_York:20261106T111500
      DTEND;TZID=America/New_York:20261106T114500
      END:VEVENT
      BEGIN:VEVENT
      UID:weekly@example.org
      RECURRENCE-ID;TZID=America/New_York:20261119T100000
      STATUS:CANCELLED
      END:VEVENT
      BEGIN:VEVENT
      UID:away@example.org
      SUMMARY:Away
      DTSTART;VALUE=DATE:20261107
      DTEND;VALUE=DATE:20261109
      END:VEVENT
      BEGIN:VEVENT
      UID:unsupported@example.org
      DTSTART:20261101T100000Z
      RRULE:FREQ=HOURLY
      END:VEVENT
      END:VCALENDAR
    ICS
    upload = Rack::Test::UploadedFile.new(StringIO.new(data), "text/calendar", true, original_filename: "history.ics")
    post dashboard_mail_calendar_preview_path(account_id: @account.id),
      params: {calendar_file: upload, team_mailbox_id: @row.id}, headers: as(@member)
    assert_response :see_other
    LightekMail::CalendarHistoryPreview.where(account: @account).sole
  end

  def apply_preview(preview)
    post dashboard_mail_calendar_review_path(account_id: @account.id, id: preview.id), headers: as(@member)
    assert_response :see_other
    refute LightekMail::CalendarHistoryPreview.exists?(preview.id)
  end

  def as(user)
    {"X-Test-User" => user.id.to_s}
  end
end
