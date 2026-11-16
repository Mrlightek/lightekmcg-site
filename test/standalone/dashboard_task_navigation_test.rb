# Permission-filtered defaults must retain the same destinations when grouped.
require_relative '../../app/helpers/nevaeh_control_center_helper'
class String
  def in?(values) = values.include?(self)
end
module Marlon; class Ticket; end; end
class NevaehWorkflow; end
module LightekPwa
  module Policy
    def self.administration_available_for?(user) = user.role == 'super_admin'
  end
end
module LightekAgency
  module PackagePolicy
    def self.runtime_accounts = self
    def self.exists? = false
  end
end
class NavigationView
  include NevaehControlCenterHelper
  User = Struct.new(:role, :studio, :commerce, :staff) do
    def can_access_feature?(feature) = {'studio' => studio, 'commerce_workspace' => commerce}.fetch(feature, false)
    def employee? = staff
  end
  attr_accessor :current_user
  def initialize(role, studio: false, commerce: false, staff: false)
    @current_user = User.new(role, studio, commerce, staff)
  end
  def main_app = self
  def dymond_dash = self
  def root_path = '/dashboard'
  def method_missing(name, *) = "/#{name}"
  def can?(*args) = true
end
def check(value, message)
  raise message unless value
end
operator = NavigationView.new('super_admin', commerce: true, staff: true).nevaeh_navigation_defaults
ids = operator.map { |row| row.fetch('id') }
check(ids.uniq == ids, 'A destination was duplicated')
check(%w[overview servers infrastructure vault finance studio white-label demos connect tickets new-ticket factory capabilities settings].all? { |id| ids.include?(id) }, 'Operator tools were lost')
check(operator.find { |r| r['id'] == 'overview' }['group'] == 'Start', 'Home is not in Start')
check(operator.find { |r| r['id'] == 'servers' }['group'] == 'Technical tools', 'Servers mixed into daily business')
check(operator.find { |r| r['id'] == 'commerce' }['group'] == 'Business & money', 'Commerce group incorrect')
client = NavigationView.new('client').nevaeh_navigation_defaults
check((client.map { |r| r['id'] } & %w[infrastructure vault finance studio commerce shipping white-label demos connect tickets pwa]).empty?, 'Grouping exposed restricted destinations')
check(client.find { |r| r['id'] == 'overview' }['path'] == '/dashboard_client_home_path', 'Client home was changed')
agency = NavigationView.new('white_label', studio: true, commerce: true).nevaeh_navigation_defaults
check(%w[studio commerce shipping white-label connect reseller-packages].all? { |id| agency.any? { |r| r['id'] == id } }, 'Agency destinations lost')
check(agency.none? { |r| %w[infrastructure vault finance].include?(r['id']) }, 'Agency gained platform tools')
puts 'Task navigation: operator, agency and client destination checks passed'
