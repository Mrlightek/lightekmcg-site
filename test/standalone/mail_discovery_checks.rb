require "tmpdir"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "minitest/autorun"
require "minitest/mock"
require "rack/test"
require "zip"

ROOT = File.expand_path("../..", __dir__)
STORAGE_ROOT = Dir.mktmpdir("lightek-mail-discovery")
Minitest.after_run { FileUtils.rm_rf(STORAGE_ROOT) }
ENV["DATABASE_URL"] = "sqlite3::memory:"

class MailDiscoveryTestApp < Rails::Application
  config.root = STORAGE_ROOT
  config.eager_load = false
  config.active_support.to_time_preserves_timezone = :zone
  config.secret_key_base = "mail-retention-test-" * 8
  config.logger = Logger.new(File::NULL)
  config.hosts.clear
  config.active_storage.service = :test
  config.active_storage.service_configurations = {test: {service: "Disk", root: STORAGE_ROOT}}
  config.active_job.queue_adapter = :test
  config.action_view.form_with_generates_ids = true
end

Rails.application.initialize!
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) do |t|
    t.string :role, default: "client"
    t.string :email
    t.datetime :access_suspended_at
  end
  create_table(:lightek_test_employments) do |t|
    t.references :employer
    t.references :worker
    t.boolean :active, default: true
  end
  create_table(:lightek_team_channels) { |table| table.references :employer, null: false }
  create_table(:lightek_office_files) do |table|
    table.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels}
    table.references :creator, null: false, foreign_key: {to_table: :users}
    table.references :editor, null: false, foreign_key: {to_table: :users}
    table.string :kind, null: false
    table.string :title, null: false
    table.text :content, null: false
    table.boolean :rich_text, default: false, null: false
    table.integer :lock_version, default: 0, null: false
    table.timestamps
  end
  create_table(:action_mailbox_inbound_emails)
  create_table(:lightek_mail_sending_policies) { |t| t.boolean :sending_enabled; t.string :stop_reason }
  create_table(:active_storage_blobs) do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
  end
  create_table(:active_storage_attachments) do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true
    t.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}
    t.datetime :created_at, null: false
  end
end

%w[20261026150000_create_lightek_mail_studio 20261113140000_add_lightek_mailbox_management
   20261122196000_add_shared_workspace 20261123090000_add_office_files_to_shared_drives
   20261123170000_add_mail_discovery 20261123173000_add_discovery_drive_holds].each { |migration| require File.join(ROOT, "db/migrate", migration) }
CreateLightekMailStudio.new.migrate(:up)
AddLightekMailboxManagement.new.migrate(:up)
AddSharedWorkspace.new.migrate(:up)
AddOfficeFilesToSharedDrives.new.migrate(:up)
AddMailDiscovery.new.migrate(:up)
AddDiscoveryDriveHolds.new.migrate(:up)

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class User < ApplicationRecord
  def can_access_feature?(feature) = feature == "mail"
  def full_name = email.to_s.split("@").first
end
module LightekPeople
  class Employment < ApplicationRecord
    self.table_name = "lightek_test_employments"
    belongs_to :employer, class_name: "User"
    belongs_to :worker, class_name: "User"
    scope :active, -> { where(active: true) }
    def active_on?(_date) = active?
  end
end
module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    belongs_to :user
    has_many :messages, class_name: "LightekMail::Message"
    scope :mailboxes, -> { where(deleted_at: nil, mailbox_kind: "mailbox") }
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
%w[models/lightek_mail/message models/lightek_mail/retention_rule models/lightek_mail/matter
   models/lightek_mail/matter_hold models/lightek_mail/matter_reviewer models/lightek_mail/retained_message
   models/lightek_mail/discovery_event services/lightek_people/access services/lightek_people/lifecycle_access
   services/lightek_team/workspace services/lightek_mail/access services/lightek_mail/submission
   services/lightek_mail/retention services/lightek_mail/discovery_access services/lightek_mail/discovery_search
   services/lightek_mail/discovery_export controllers/dashboard/mail_studio_controller
   controllers/dashboard/mail_discovery_controller
   controllers/dashboard/shared_workspace_controller controllers/dashboard/shared_drives_controller
   models/lightek_workspace/drive models/lightek_workspace/drive_entry models/lightek_workspace/drive_member
   models/lightek_workspace/discovery_drive_hold models/lightek_office/shared_file models/lightek_office/revision
   services/lightek_office/content services/lightek_office/document services/lightek_office/changes
   services/lightek_workspace/drive_discovery controllers/dashboard/team_office_controller jobs/application_job jobs/lightek_mail/expire_retained_mail_job].each do |path|
  require File.join(ROOT, "app", path)
end
Dashboard::MailDiscoveryController.prepend_view_path(File.join(ROOT, "app/views"))

MailDiscoveryTestApp.routes.draw do
  get "/dashboard/mail", to: "dashboard/mail_studio#index", as: :dashboard_mail
  delete "/dashboard/mail/accounts/:account_id/messages/:id", to: "dashboard/mail_studio#purge_message",
    as: :purge_dashboard_mail_message
  get "/dashboard/mail/accounts/:account_id/messages/:id/attachments/:attachment_id", to: "dashboard/mail_studio#attachment",
    as: :dashboard_mail_attachment
  instance_eval(File.read(File.join(ROOT, "config/routes/mail_discovery.rb")))
  instance_eval(File.read(File.join(ROOT, "config/routes/executive_operations.rb")))
end

class MailDiscoveryChecks < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  def setup
    @owner = User.create!(email: "workspace-owner@example.test")
    @reviewer = User.create!(email: "reviewer@example.test", role: "employee")
    @outsider = User.create!(email: "other-owner@example.test", role: "super_admin")
    @employment = LightekPeople::Employment.create!(employer: @owner, worker: @reviewer)
    @mailbox = account(@owner, "mail")
    @outside_mailbox = account(@outsider, "external")
    @personal_mailbox = account(@reviewer, "personal")
  end

  def test_hold_survives_mail_studio_purge_and_exports_evidence_only_to_authorized_reviewers
    original = create_mail(@mailbox, "Held receipt", created_at: 2.years.ago)
    original.source.attach(io: StringIO.new("From: sender@example.test\r\n\r\nRaw message"), filename: "original.eml")
    original.attachments.attach(io: StringIO.new("receipt contents"), filename: "receipt.txt")
    matter = create_matter

    post hold_dashboard_mail_matter_path(matter), params: {account_id: @personal_mailbox.id}, headers: as(@owner)
    assert_response :not_found
    post hold_dashboard_mail_matter_path(matter), params: {account_id: @outside_mailbox.id}, headers: as(@owner)
    assert_response :not_found
    place_hold(matter)
    post grant_dashboard_mail_matter_path(matter), params: {reviewer_id: @outsider.id}, headers: as(@owner)
    assert_response :not_found
    post grant_dashboard_mail_matter_path(matter), params: {reviewer_id: @reviewer.id}, headers: as(@owner)
    assert_response :see_other

    delete purge_dashboard_mail_message_path(account_id: @mailbox.id, id: original.id), headers: as(@owner)
    assert_response :see_other
    refute @mailbox.messages.exists?(original.id)
    retained = LightekMail::RetainedMessage.find_by!(original_id: original.id)
    retained.attachments.each { |attachment| ActiveStorage::PurgeJob.perform_now(attachment.blob) }
    assert_equal "receipt contents", retained.attachments.first.download
    assert retained.source.download.end_with?("Raw message")
    LightekMail::ExpireRetainedMailJob.perform_now
    assert LightekMail::RetainedMessage.exists?(retained.id)

    query = {account_id: @mailbox.id, mail_discovery_query: "receipt"}
    get dashboard_mail_discovery_path, headers: as(@reviewer)
    assert_response :success
    assert_includes response.body, matter.name
    refute_includes response.body, "Create matter"
    post search_dashboard_mail_matter_path(matter), params: query, headers: as(@reviewer)
    assert_response :success
    assert_includes response.body, "Held receipt"
    assert_includes response.body, "Preserved after deletion"
    assert_equal "private, no-store", response.headers["Cache-Control"]
    post search_dashboard_mail_matter_path(matter), params: query.merge(from_date: Date.current.iso8601), headers: as(@reviewer)
    assert_response :success
    assert_includes response.body, "No messages matched"

    post export_dashboard_mail_matter_path(matter), params: query, headers: as(@reviewer)
    assert_response :success
    assert_equal "application/zip", response.media_type
    export = response.body.b
    Zip::File.open_buffer(StringIO.new(export)) do |zip|
      manifest = JSON.parse(zip.read("manifest.json"))
      entry = manifest.fetch("messages").sole
      assert_equal original.id, entry.fetch("id")
      metadata = zip.read(entry.fetch("metadata_path"))
      assert_equal "Held receipt", JSON.parse(metadata).fetch("subject")
      assert_equal Digest::SHA256.hexdigest(metadata), entry.fetch("metadata_sha256")
      assert_equal "receipt contents", zip.read("messages/#{original.id}/attachment-1.txt")
      assert_match(/Raw message$/, zip.read("messages/#{original.id}/message.eml"))
    end
    event = LightekMail::DiscoveryEvent.find_by!(matter: matter, action: "mail_exported")
    assert_equal @reviewer.id, event.actor_id
    assert_equal Digest::SHA256.hexdigest(export), event.details.fetch("sha256")
    assert_equal 1, event.result_count

    post export_dashboard_mail_matter_path(matter), params: query, headers: as(@outsider)
    assert_response :not_found
    post search_dashboard_mail_matter_path(matter), params: query.merge(account_id: @outside_mailbox.id), headers: as(@reviewer)
    assert_response :not_found
    delete release_dashboard_mail_matter_path(matter), params: {account_id: @mailbox.id}, headers: as(@reviewer)
    assert_response :forbidden
    @employment.update!(active: false)
    post export_dashboard_mail_matter_path(matter), params: query, headers: as(@reviewer)
    assert_response :not_found
    delete release_dashboard_mail_matter_path(matter), params: {account_id: @mailbox.id}, headers: as(@owner)
    assert_response :see_other
    LightekMail::ExpireRetainedMailJob.perform_now
    refute LightekMail::RetainedMessage.exists?(retained.id)
  end

  def test_retention_preview_respects_message_date_and_overlapping_holds
    old = create_mail(@mailbox, "Old", created_at: 60.days.ago)
    recent = create_mail(@mailbox, "Recent", created_at: 5.days.ago)
    draft = create_mail(@mailbox, "Draft", state: "draft", direction: "outbound")
    sent = create_mail(@mailbox, "Recently sent", state: "sent", direction: "outbound",
      created_at: 60.days.ago, submitted_at: 5.days.ago)
    post dashboard_mail_retention_path, params: {account_id: @mailbox.id, operation: "preview", days: 30}, headers: as(@owner)
    assert_response :success
    assert_includes response.body, "2 current messages"
    assert_empty LightekMail::RetentionRule.where(account: @mailbox)
    post dashboard_mail_retention_path, params: {account_id: @mailbox.id, operation: "save", days: 30}, headers: as(@owner)
    assert_response :see_other
    assert_equal 30, LightekMail::RetentionRule.find_by!(account: @mailbox).days

    [old, recent, draft, sent].each do |message|
      delete purge_dashboard_mail_message_path(account_id: @mailbox.id, id: message.id), headers: as(@owner)
      assert_response :see_other
    end
    assert_equal [recent.id, sent.id].sort, LightekMail::RetainedMessage.where(account: @mailbox).pluck(:original_id).sort
    first = create_matter
    second = create_matter
    post search_dashboard_mail_matter_path(first), params: {
      account_id: @mailbox.id, mail_discovery_query: "Recently sent", from_date: 10.days.ago.to_date.iso8601
    }, headers: as(@owner)
    assert_response :success
    assert_includes response.body, "Recently sent"
    place_hold(first)
    place_hold(second)
    delete release_dashboard_mail_matter_path(first), params: {account_id: @mailbox.id}, headers: as(@owner)
    travel 45.days do
      LightekMail::ExpireRetainedMailJob.perform_now
      assert LightekMail::RetainedMessage.exists?(original_id: recent.id)
      delete release_dashboard_mail_matter_path(second), params: {account_id: @mailbox.id}, headers: as(@owner)
      LightekMail::ExpireRetainedMailJob.perform_now
      refute LightekMail::RetainedMessage.exists?(original_id: recent.id)
    end
  end

  def test_shared_drive_hold_exports_revision_and_upload_to_a_scoped_reviewer
    editor = User.create!(role: "employee", email: "editor@example.test")
    LightekPeople::Employment.create!(employer: @owner, worker: editor)
    drive = LightekWorkspace::Drive.create!(employer: @owner, name: "Records Drive")
    drive.members.create!(user: editor, role: "editor")
    other_drive = LightekWorkspace::Drive.create!(employer: @outsider, name: "Other Drive")
    unheld_drive = LightekWorkspace::Drive.create!(employer: @owner, name: "Unheld Drive")
    matter = create_matter
    post hold_dashboard_discovery_drive_path(matter), params: {drive_id: other_drive.id}, headers: as(@owner)
    assert_response :not_found
    post hold_dashboard_discovery_drive_path(matter), params: {drive_id: drive.id}, headers: as(@owner)
    assert_response :see_other
    post grant_dashboard_mail_matter_path(matter), params: {reviewer_id: @reviewer.id}, headers: as(@owner)
    assert_response :see_other

    post dashboard_drive_office_path(drive, employer_id: @owner.id), params: {
      office_file: {kind: "document", title: "Original brief", content: "First edition"}
    }, headers: as(editor)
    assert_response :see_other
    file = drive.entries.find_by!(name: "Original brief").office_file
    patch update_dashboard_drive_office_path(drive, file, employer_id: @owner.id), params: {
      office_file: {title: "Final brief", content: "Second edition", lock_version: file.lock_version}
    }, headers: as(editor)
    assert_response :see_other
    assert_equal "Second edition", file.reload.content
    revision = LightekOffice::Changes.revisions(file).sole
    upload = drive.entries.create!(creator: editor, folder: false, name: "Original receipt",
      upload: {io: StringIO.new("receipt bytes"), filename: "receipt.txt"})
    assert_raises(ActiveRecord::RecordNotDestroyed) { revision.destroy! }
    assert_raises(ActiveRecord::RecordNotDestroyed) { file.destroy! }
    assert_raises(ActiveRecord::RecordNotDestroyed) { upload.destroy! }
    refute upload.update(upload: {io: StringIO.new("replacement"), filename: "replacement.txt"})
    assert_equal "receipt bytes", upload.reload.upload.download

    get dashboard_shared_drive_path(drive, employer_id: @owner.id), headers: as(@reviewer)
    assert_response :not_found
    assert_empty drive.members.where(user: @reviewer)
    query = {drive_id: drive.id, drive_discovery_query: "Original", drive_from: Date.current.iso8601}
    post search_dashboard_discovery_drive_path(matter), params: query, headers: as(@reviewer)
    assert_response :success
    assert_includes response.body, "Original brief"
    assert_includes response.body, "Earlier version"
    assert_includes response.body, "Original receipt"
    refute_includes response.body, "Final brief"
    assert_equal "private, no-store", response.headers["Cache-Control"]

    post export_dashboard_discovery_drive_path(matter), params: query, headers: as(@reviewer)
    assert_response :success
    assert_equal "application/zip", response.media_type
    digest = Digest::SHA256.hexdigest(response.body.b)
    Zip::File.open_buffer(StringIO.new(response.body.b)) do |zip|
      items = JSON.parse(zip.read("manifest.json")).fetch("files").index_by { |item| item.fetch("name") }
      assert_equal 2, items.size
      original = items.fetch("Original brief")
      payload = zip.read(original.fetch("path"))
      assert_equal "First edition", JSON.parse(payload).fetch("content")
      assert_equal 0, original.fetch("version")
      assert_equal Digest::SHA256.hexdigest(payload), original.fetch("sha256")
      receipt = items.fetch("Original receipt")
      assert_equal "receipt bytes", zip.read(receipt.fetch("path"))
    end
    event = LightekMail::DiscoveryEvent.find_by!(matter: matter, drive: drive, action: "drive_exported")
    assert_equal @reviewer.id, event.actor_id
    assert_equal digest, event.details.fetch("sha256")

    post export_dashboard_discovery_drive_path(matter), params: query, headers: as(@outsider)
    assert_response :not_found
    post search_dashboard_discovery_drive_path(matter), params: {drive_id: unheld_drive.id}, headers: as(@reviewer)
    assert_response :not_found
    delete release_dashboard_discovery_drive_path(matter), params: {drive_id: drive.id}, headers: as(@reviewer)
    assert_response :forbidden
    second_matter = create_matter
    post hold_dashboard_discovery_drive_path(second_matter), params: {drive_id: drive.id}, headers: as(@owner)
    assert_response :see_other
    delete release_dashboard_discovery_drive_path(matter), params: {drive_id: drive.id}, headers: as(@owner)
    assert_response :see_other
    post export_dashboard_discovery_drive_path(matter), params: query, headers: as(@reviewer)
    assert_response :not_found
    assert_raises(ActiveRecord::RecordNotDestroyed) { revision.destroy! }
    delete release_dashboard_discovery_drive_path(second_matter), params: {drive_id: drive.id}, headers: as(@owner)
    assert_response :see_other
    assert revision.destroy!
  end

  private

  def as(user) = {"X-Test-User" => user.id.to_s}

  def account(user, name)
    domain = "workspace-#{user.id}.test"
    domain_id = ActiveRecord::Base.connection.execute(
      "INSERT INTO lightek_mail_domains (user_id, name, verification_token, created_at, updated_at) " \
      "VALUES (#{user.id}, '#{domain}', 'test', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id"
    ).first.fetch("id")
    LightekMail::Account.create!(user: user, domain_id: domain_id, address: "#{name}@#{domain}", display_name: name)
  end

  def create_mail(mailbox, subject, **attributes)
    mailbox.messages.create!({subject: subject, message_id: SecureRandom.uuid, state: "inbox",
      direction: "inbound", from_address: "sender@example.test", trashed: true, text_body: "Message body"}.merge(attributes))
  end

  def create_matter
    post dashboard_mail_matters_path, params: {mail_matter_name: "Records review"}, headers: as(@owner)
    assert_response :see_other
    LightekMail::Matter.where(employer: @owner).last!
  end

  def place_hold(matter)
    post hold_dashboard_mail_matter_path(matter), params: {account_id: @mailbox.id}, headers: as(@owner)
    assert_response :see_other
  end
end
