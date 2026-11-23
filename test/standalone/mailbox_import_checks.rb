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
  create_table(:users) { |table| table.string :role, default: "client" }
end
require File.join(ROOT, "db/migrate/20261026150000_create_lightek_mail_studio")
require File.join(ROOT, "db/migrate/20261123145000_add_mailbox_imports")
CreateLightekMailStudio.new.migrate(:up)
AddMailboxImports.new.migrate(:up)
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
module Dashboard; end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    def current_user = User.find(request.headers.fetch("X-Test-User"))
  end
end

%w[models/lightek_mail/message models/lightek_mail/mailbox_import services/lightek_mail/access
   services/lightek_mail/inbound services/lightek_mail/conversation services/lightek_mail/template_renderer
   services/lightek_mail/search services/lightek_mail/mbox_reader services/lightek_mail/mbox_message
   services/lightek_mail/mailbox_import_runner jobs/application_job jobs/lightek_mail/mailbox_import_job
   controllers/dashboard/mailbox_imports_controller].each { |path| require File.join(ROOT, "app", path) }

class MailboxImportChecks < ActionController::TestCase
  tests Dashboard::MailboxImportsController

  def setup
    @owner = User.create!
    @other_user = User.create!
    @account = mailbox(@owner, "owner-#{@owner.id}@example.net")
    @other_account = mailbox(@other_user, "other-#{@other_user.id}@example.net")
    @request.set_header("HTTP_X_TEST_USER", @owner.id.to_s)
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw do
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
      :dashboard_mailbox_import_path, :start_dashboard_mailbox_import_path, :retry_dashboard_mailbox_import_path)
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
