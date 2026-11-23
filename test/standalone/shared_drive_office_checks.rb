# frozen_string_literal: true

require 'minitest/autorun'
require 'active_record'
require 'active_support/all'
require 'action_controller'
require 'action_controller/test_case'

ROOT = File.expand_path('../..', __dir__)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # The native Office files in this suite have no Active Storage uploads.
  def self.has_one_attached(name)
    define_method(name) { Struct.new(:attached?).new(false) }
  end
end

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
end

require File.join(ROOT, 'db/migrate/20261122196000_add_shared_workspace')
require File.join(ROOT, 'db/migrate/20261123090000_add_office_files_to_shared_drives')
AddSharedWorkspace.new.migrate(:up)
AddOfficeFilesToSharedDrives.new.migrate(:up)

class User < ApplicationRecord
end

module LightekPeople
  module Access
    class Denied < StandardError; end
  end
end

module LightekTeam
  class Channel < ApplicationRecord
    self.table_name = 'lightek_team_channels'
  end

  # Replace authentication and employment lookup at the private-engine boundary.
  class Workspace
    def self.employers_for(_actor)
      User.where(full_name: ['Organization', 'Other organization'])
    end

    def initialize(actor:, employer:)
      @employer = employer
    end

    def channels = Channel.where(employer_id: @employer.id)
  end
end

module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    def current_user = User.find(request.headers['X-Test-User'])
  end
end

module Dashboard
end

%w[models/lightek_workspace/drive models/lightek_workspace/drive_member models/lightek_workspace/drive_entry
   models/lightek_office/revision models/lightek_office/shared_file services/lightek_office/content
   services/lightek_office/document services/lightek_office/changes controllers/dashboard/team_office_controller].each do |path|
  require File.join(ROOT, 'app', path)
end

class SharedDriveOfficeChecks < ActionController::TestCase
  tests Dashboard::TeamOfficeController
  tests_view_path = File.join(ROOT, 'app/views')
  Dashboard::TeamOfficeController.prepend_view_path(tests_view_path)

  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { instance_eval(File.read(File.join(ROOT, 'config/routes/executive_operations.rb'))) }
    @controller.extend(@routes.url_helpers)
    Dashboard::TeamOfficeController.helper_method(:dashboard_shared_drive_path)
    Dashboard::TeamOfficeController.helper do
      def l(value, **) = value.to_s
    end
    @owner = User.create!(full_name: 'Organization')
    @editor = User.create!(full_name: 'Editor')
    @viewer = User.create!(full_name: 'Viewer')
    @other = User.create!(full_name: 'Other organization')
    @drive = LightekWorkspace::Drive.create!(employer: @owner, name: 'Production')
    @folder = @drive.entries.create!(creator: @owner, name: 'Briefs', folder: true)
    @drive.members.create!(user: @editor, role: 'editor')
    @drive.members.create!(user: @viewer, role: 'viewer')
    use_actor(@editor)
  end

  def test_create_edit_restore_and_read_the_same_drive_document
    file = create_document
    assert_equal @folder.id, file.drive_entry.parent_id
    assert_equal 'Opening', file.drive_entry.name
    assert_nil file.channel_id

    patch :update, params: location.merge(file_id: file.id, office_file: {title: 'ignored for autosave',
      content: 'Revision', lock_version: file.lock_version}), as: :json
    assert_response :success
    assert_equal 'Revision', file.reload.content

    post :restore, params: location.merge(file_id: file.id, version: 0, lock_version: file.lock_version)
    assert_response :see_other
    assert_equal 'First draft', file.reload.content

    use_actor(@viewer)
    get :export, params: location.merge(file_id: file.id)
    assert_response :success
    assert_equal 'First draft', response.body

    patch :update, params: location.merge(file_id: file.id, office_file: {content: 'Denied',
      lock_version: file.lock_version}), as: :json
    assert_response :forbidden
    assert_equal 'First draft', file.reload.content

    use_actor(@other)
    get :live, params: location.merge(file_id: file.id), as: :json
    assert_response :not_found
  end

  def test_editor_and_viewer_render_different_controls
    get :index, params: location.merge(folder: @folder.id, kind: 'spreadsheet')
    assert_response :success
    assert_includes response.body, 'data-office-grid-source="true"'
    assert_includes response.body, 'Save shared file'

    file = create_document
    use_actor(@viewer)
    get :index, params: location.merge(file_id: file.id)
    assert_response :success
    assert_includes response.body, 'First draft'
    assert_includes response.body, 'Download'
    refute_includes response.body, 'Save shared file'
  end

  def test_document_title_updates_the_drive_listing_and_failed_creation_leaves_no_entry
    file = create_document
    patch :update, params: location.merge(file_id: file.id, office_file: {title: 'Renamed brief',
      content: 'New text', lock_version: file.lock_version})
    assert_response :see_other
    assert_equal 'Renamed brief', file.drive_entry.reload.name

    count = @drive.entries.count
    post :create, params: location.merge(folder: @folder.id,
      office_file: {kind: 'document', title: 'Invalid file', content: ''}), as: :json
    assert_response :unprocessable_entity
    assert_equal count, @drive.entries.count
  end

  def test_drive_and_channel_are_distinct_file_locations
    file = create_document
    channel = LightekTeam::Channel.create!(employer_id: @owner.id)
    channel_file = LightekOffice::SharedFile.create!(channel: channel, creator: @owner, editor: @owner,
      title: 'Channel file', kind: 'document', content: 'Channel content')

    get :live, params: location.merge(file_id: channel_file.id), as: :json
    assert_response :not_found
    get :live, params: {channel_id: channel.id, employer_id: @owner.id, file_id: file.id}, as: :json
    assert_response :not_found
    get :live, params: {channel_id: channel.id, employer_id: @owner.id, file_id: channel_file.id}, as: :json
    assert_response :success
  end

  private

  def use_actor(user) = @request.set_header('HTTP_X_TEST_USER', user.id.to_s)
  def location = {drive_id: @drive.id, employer_id: @owner.id}

  def create_document
    post :create, params: location.merge(folder: @folder.id,
      office_file: {kind: 'document', title: 'Opening', content: 'First draft'})
    assert_response :see_other
    @folder.reload
    @drive.entries.where(parent: @folder).find_by!(name: 'Opening').office_file
  end
end
