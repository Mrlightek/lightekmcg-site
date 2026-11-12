require 'minitest/autorun'
require 'erb'
require_relative '../../app/helpers/nevaeh_control_center_helper'
class DashboardBreadcrumbsTest < Minitest::Test
  class View
    include NevaehControlCenterHelper
    attr_accessor :request, :entries
    def initialize(path)
      @request = Struct.new(:path).new(path)
      @entries = [{'path'=>'/dashboard/commerce', 'label'=>'Commerce'}, {'path'=>'/dashboard/rooms', 'label'=>'Rooms & guests'}, {'path'=>'/dashboard/studio', 'label'=>'Studio'}]
    end
    def nevaeh_sidebar_entries = entries
    def dymond_dash = Struct.new(:root_path).new('/dashboard')
    def main_app = Struct.new(:dashboard_live_path, :dashboard_session_media_path).new('/dashboard/live', '/dashboard/reservations/media')
    def select_site(id) = @site = Struct.new(:id).new(id)
  end
  def test_nested_page_links_to_its_workspace_and_keeps_site_context
    view = View.new('/dashboard/commerce/orders/12');view.select_site(7)
    crumbs = view.nevaeh_dashboard_breadcrumbs(page_label: 'Order 12')
    assert_equal ['Dashboard', 'Commerce', 'Order 12'], crumbs.map { |row| row[:label] }
    assert_equal '/dashboard/commerce?site_id=7', crumbs[1][:path]
    assert_nil crumbs.last[:path]
  end
  def test_current_workspace_is_not_a_duplicate_link_and_hidden_entries_are_excluded
    view = View.new('/dashboard/rooms')
    assert_equal [{label:'Dashboard',path:'/dashboard'},{label:'Rooms & guests',path:nil}], view.nevaeh_dashboard_breadcrumbs(page_label:'Rooms')
    view.entries.first['hidden'] = true;view.request.path = '/dashboard/commerce/orders'
    assert_equal ['Dashboard','Orders'], view.nevaeh_dashboard_breadcrumbs(page_label:'Orders').map { |row| row[:label] }
  end
  def test_external_navigation_entries_are_not_used_as_breadcrumbs
    view = View.new('/dashboard/live');view.entries << {'path'=>'//example.com/dashboard/live','label'=>'External'}
    assert_equal ['Dashboard','Live Studio'], view.nevaeh_dashboard_breadcrumbs(page_label:'On air').map { |row| row[:label] }
  end
end
