require "tmpdir"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "minitest/autorun"
require "rack/test"
require "zip"

ROOT = File.expand_path("../..", __dir__)
TEMP_ROOT = Dir.mktmpdir("lightek-drive-import")
Minitest.after_run { FileUtils.rm_rf(TEMP_ROOT) }
ENV["DATABASE_URL"] = "sqlite3::memory:"

class SharedDriveZipTestApp < Rails::Application
  config.root = TEMP_ROOT
  config.eager_load = false
  config.active_support.to_time_preserves_timezone = :zone
  config.secret_key_base = "drive-import-checks-" * 10
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
  create_table(:users) { |table| table.string :full_name }
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
%w[20261122196000_add_shared_workspace 20261123090000_add_office_files_to_shared_drives
   20261123161000_add_shared_drive_imports].each { |name| require File.join(ROOT, "db/migrate", name) }
AddSharedWorkspace.new.migrate(:up)
AddOfficeFilesToSharedDrives.new.migrate(:up)
AddSharedDriveImports.new.migrate(:up)

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class ApplicationJob < ActiveJob::Base; end
class User < ApplicationRecord; end
module LightekPeople
  module Access
    class Denied < StandardError; end
  end
end
module LightekTeam
  class Channel < ApplicationRecord
    self.table_name = "lightek_team_channels"
  end
  class Workspace
    def self.employers_for(_actor) = User.where(full_name: "Organization")
    def initialize(actor:, employer:); end
    def roster = User.all
  end
end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    helper_method :current_user
    def current_user = User.find(request.headers.fetch("X-Test-User"))
  end
end
module Dashboard; end

%w[models/lightek_workspace/drive models/lightek_workspace/drive_entry models/lightek_workspace/drive_member
   models/lightek_workspace/drive_import models/lightek_workspace/drive_import_receipt
   models/lightek_office/shared_file models/lightek_office/revision services/lightek_office/content
   services/lightek_office/document services/lightek_office/changes services/lightek_office/word_import
   services/lightek_office/excel_import services/lightek_office/powerpoint_import
   services/lightek_accounting/workbook_schema services/lightek_accounting/sheet_formula
   services/lightek_workspace/drive_archive services/lightek_workspace/drive_import_runner jobs/lightek_workspace/drive_import_job
   controllers/dashboard/shared_workspace_controller controllers/dashboard/shared_drives_controller
   controllers/dashboard/shared_drive_imports_controller controllers/dashboard/team_office_controller].each do |path|
  require File.join(ROOT, "app", path)
end

SharedDriveZipTestApp.routes.draw do
  instance_eval(File.read(File.join(ROOT, "config/routes/executive_operations.rb")))
end

class SharedDriveZipImportChecks < ActionDispatch::IntegrationTest
  def setup
    @owner = User.create!(full_name: "Organization")
    @editor = User.create!(full_name: "Editor")
    @viewer = User.create!(full_name: "Viewer")
    @outsider = User.create!(full_name: "Outside this drive")
    @drive = LightekWorkspace::Drive.create!(employer: @owner, name: "Creative")
    @target = @drive.entries.create!(creator: @owner, name: "Team projects", folder: true)
    @drive.members.create!(user: @editor, role: "editor")
    @drive.members.create!(user: @viewer, role: "viewer")
    [Dashboard::SharedDriveImportsController, Dashboard::SharedDrivesController, Dashboard::TeamOfficeController].each do |controller|
      controller.prepend_view_path(File.join(ROOT, "app/views"))
    end
  end

  def test_nested_import_edit_download_permissions_and_repeat
    get dashboard_shared_drive_imports_path(@drive, **employer, folder: @target.id), headers: as(@editor)
    assert_response :success
    assert_includes response.body, "Preview import"

    run = preview(project)
    assert_equal "preview", run.state
    assert_equal 1, @drive.entries.count
    get dashboard_shared_drive_import_path(@drive, run, **employer), headers: as(@editor)
    assert_response :success
    assert_includes response.body, "Production/Brief.docx"
    assert_includes response.body, "Kept as a download"
    assert_includes response.body, "Spreadsheet"

    start(run)
    assert_equal "complete", run.state, run.error_message
    root = @drive.entries.where(parent: @target).find_by!(name: "Production")
    nested = @drive.entries.where(parent: root).find_by!(name: "Numbers")
    document = @drive.entries.where(parent: root).find_by!(name: "Brief.docx").office_file
    sheet = @drive.entries.where(parent: nested).find_by!(name: "Budget.xlsx").office_file
    asset = @drive.entries.where(parent: nested).find_by!(name: "Sample.pdf")
    assert_equal "document", document.kind
    assert_includes document.content, "Original brief"
    slides = @drive.entries.where(parent: root).find_by!(name: "Agenda.pptx").office_file
    assert_equal "presentation", slides.kind
    assert_equal "Opening agenda", LightekOffice::Content.slides(slides.content).first.first
    assert_equal "spreadsheet", sheet.kind
    assert_includes sheet.content, "42"
    assert_equal "pdf fixture", asset.upload.download

    patch update_dashboard_drive_office_path(@drive, document, **employer),
      params: {office_file: {title: "Updated brief", content: "<p>Edited document</p>", rich_text: true, lock_version: document.lock_version}},
      headers: as(@editor)
    assert_response :see_other
    assert_includes document.reload.content, "Edited document"
    patch update_dashboard_drive_office_path(@drive, sheet, **employer),
      params: {office_file: {title: "Budget.xlsx", content: "43", lock_version: sheet.lock_version}}, headers: as(@editor)
    assert_response :see_other
    assert_equal "43", sheet.reload.content

    get download_dashboard_shared_drive_path(@drive, asset, **employer), headers: as(@viewer)
    assert_response :success
    get download_dashboard_shared_drive_path(@drive, asset, **employer), headers: as(@outsider)
    assert_response :not_found
    get export_dashboard_drive_office_path(@drive, document, **employer), headers: as(@outsider)
    assert_response :not_found

    before = @drive.entries.count
    repeated = preview(project)
    assert repeated.items.all? { |item| item.fetch("status") == "duplicate" }
    start(repeated)
    assert_equal "complete", repeated.state
    assert_equal before, @drive.entries.count
    assert_equal "Updated brief", document.reload.title
    assert_equal "43", sheet.reload.content
  end

  def test_rejects_unsafe_paths_and_read_only_uploads
    post dashboard_shared_drive_imports_path(@drive, **employer), params: {archive: upload(zip("../outside.txt" => "blocked"))},
      headers: as(@editor)
    assert_response :see_other
    assert_match(/unsafe path/, flash[:alert])
    assert_empty LightekWorkspace::DriveImport.where(drive: @drive)
    get dashboard_shared_drive_imports_path(@drive, **employer), headers: as(@viewer)
    assert_response :forbidden
    post dashboard_shared_drive_imports_path(@drive, **employer), params: {archive: upload(project)}, headers: as(@viewer)
    assert_response :forbidden
    assert_equal 1, @drive.entries.count
  end

  def test_worker_rechecks_edit_access_and_retry_can_reuse_existing_folder
    folder = @drive.entries.create!(parent: @target, creator: @owner, name: "Production", folder: true)
    run = preview(project)
    assert_equal "reuse", run.items.first.fetch("status")
    post start_dashboard_shared_drive_import_path(@drive, run, **employer), headers: as(@editor)
    assert_response :see_other
    @drive.members.find_by!(user: @editor).update!(role: "viewer")
    perform(run)
    assert_equal "failed", run.state
    assert_equal 2, @drive.entries.count
    @drive.members.find_by!(user: @editor).update!(role: "editor")
    start(run)
    assert_equal "complete", run.state, run.error_message
    assert_equal folder.id, @drive.entries.where(parent: @target, folder: true, name: "Production").sole.id
  end

  private

  def employer = {employer_id: @owner.id}
  def as(actor) = {"X-Test-User" => actor.id.to_s}

  def start(run)
    post start_dashboard_shared_drive_import_path(@drive, run, **employer), headers: as(@editor)
    assert_response :see_other
    perform(run)
  end

  def perform(run)
    LightekWorkspace::DriveImportJob.perform_now(run.id, run.reload.run_token)
    run.reload
  end

  def preview(bytes)
    post dashboard_shared_drive_imports_path(@drive, **employer), params: {folder: @target.id, archive: upload(bytes)},
      headers: as(@editor)
    assert_response :see_other
    assert_nil flash[:alert], flash[:alert]
    LightekWorkspace::DriveImport.where(drive: @drive).order(:id).last!
  end

  def upload(bytes)
    # A real file allows the importer to use Zip::File without reading the full upload into memory.
    path = File.join(TEMP_ROOT, "archive-#{SecureRandom.hex(6)}.zip")
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, "application/zip", true, original_filename: "Drive.zip")
  end

  def project
    word = zip("[Content_Types].xml" => "<Types><Override PartName=\"/word/document.xml\" ContentType=\"#{LightekOffice::WordImport::WORD_PART}\"/></Types>",
      "word/document.xml" => %(<w:document xmlns:w="#{LightekOffice::WordImport::WORD_NS}"><w:body><w:p><w:r><w:t>Original brief</w:t></w:r></w:p></w:body></w:document>))
    excel = zip("xl/workbook.xml" => '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
      "xl/_rels/workbook.xml.rels" => '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      "xl/worksheets/sheet1.xml" => '<worksheet><sheetData><row r="1"><c r="A1"><v>42</v></c></row></sheetData></worksheet>')
    zip("Production/Brief.docx" => word, "Production/Numbers/Budget.xlsx" => excel,
      "Production/Numbers/Sample.pdf" => "pdf fixture", "Production/Agenda.pptx" => presentation, "Production/Unsupported.pptx" => "original presentation")
  end

  def presentation
    format = LightekOffice::PowerpointImport
    xml = ->(root, content) do
      %(<p:#{root} xmlns:p="#{format::PRESENTATION_NS}" xmlns:a="#{format::DRAWING_NS}" xmlns:r="#{format::OFFICE_RELS}">#{content}</p:#{root}>)
    end
    shape = '<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Opening agenda</a:t></a:r></a:p></p:txBody></p:sp>'
    zip("[Content_Types].xml" => %(<Types xmlns="#{format::TYPES_NS}"><Override PartName="/ppt/presentation.xml" ContentType="#{format::MAIN_TYPE}"/></Types>),
      "ppt/presentation.xml" => xml.call("presentation", '<p:sldIdLst><p:sldId id="256" r:id="one"/></p:sldIdLst>'),
      "ppt/_rels/presentation.xml.rels" => %(<Relationships xmlns="#{format::PACKAGE_RELS}"><Relationship Id="one" Type="#{format::OFFICE_RELS}/slide" Target="slides/slide1.xml"/></Relationships>),
      "ppt/slides/slide1.xml" => xml.call("sld", "<p:cSld><p:spTree>#{shape}</p:spTree></p:cSld>"))
  end

  def zip(entries)
    Zip::OutputStream.write_buffer do |archive|
      entries.each do |path, bytes|
        archive.put_next_entry(path)
        archive.write(bytes)
      end
    end.string
  end
end
