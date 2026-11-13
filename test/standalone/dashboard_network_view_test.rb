gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'active_support/all'
require 'action_view'
require 'ostruct'
require 'nokogiri'
module Gatekeeper
  module CronManagement
    ALLOWED_JOBS = ['GatekeeperDeviceHeartbeatSweepJob']
  end
end
class NetworkManagedDevice
  DEVICE_TYPES = %w[router phone]
  PROTOCOLS = %w[agent ssh]
  STATUSES = %w[registered active offline]
end
module Godaddy
  class DnsService
    TYPES = %w[A AAAA CNAME MX TXT]
  end
end
module LightekCommerce
  class Order
    def self.find_by(*) = OpenStruct.new(id: 42, paid_at?: true, provisioned_at?: false)
  end
end
module NetworkViewHelpers
  def protect_against_forgery? = false
  def flash = {}
  def method_missing(name, *args, **kwargs)
    return "/#{name}" if name.to_s.end_with?('_path')
    super
  end
  def respond_to_missing?(name, *) = name.to_s.end_with?('_path') || super
end
class DashboardNetworkViewTest < Minitest::Test
  def setup
    root = File.expand_path('../..', __dir__)
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([root+'/app/views']), {}, nil)
    view.extend(NetworkViewHelpers)
    node = OpenStruct.new(id:1,name:'Test server',provider_resource_id:'test-node',ip_address:'192.0.2.10',status:'active')
    view.assign(dashboard_warnings:[],zone:'example.com',zones:['example.com'],records:[{'recordId'=>123,'type'=>'MX','name'=>'@','data'=>'mail.example.com','ttl'=>600,'priority'=>10}],managed_nodes:[node],devices:[OpenStruct.new(id:7,name:'Test router',device_type:'router',identifier:'TEST-001',hostname:'router.example.com',management_protocol:'agent',status:'active')],cron_jobs:[OpenStruct.new(name:'dashboard_example',klass:'GatekeeperDeviceHeartbeatSweepJob',cron:'0 * * * *',status:'enabled')],provisioning_requests:[OpenStruct.new(id:8,gatekeeper_node:node,owner:OpenStruct.new(email_address:'test@example.com'),compute_provider:OpenStruct.new(name:'Test provider'),metadata:{},execution_status:'pending')],recent_network_operations:[],firewall_status:'Active')
    @doc = Nokogiri::HTML.fragment(view.render(template:'dashboard/network/index'))
  end
  def form_for(path, method)
    @doc.css('form').find { |form| form['action'] == "/#{path}_path" && (form.at_css('input[name="_method"]')&.[]('value') || form['method']).downcase == method }
  end
  def test_dns_edit_keeps_zone_record_identity_and_extended_mx_attributes
    form = form_for('dashboard_network_dns','put')
    refute_nil form
    assert_equal '5', form.ancestors('td').first['colspan']
    assert form.ancestors('details').first['class'].include?('net-dns-editor')
    %w[zone record_id dns_record[type] dns_record[name] dns_record[data] dns_record[ttl] dns_record[priority]].each { |name| assert form.css('[name]').any? { |field| field['name'] == name }, name }
    assert_equal '10', form.css('input').find { |field| field['name'] == 'dns_record[priority]' }['value']
    assert form_for('dashboard_network_dns','post')
    assert form_for('dashboard_network_dns','delete')
  end
  def test_existing_infrastructure_and_schedule_actions_remain_available
    {'dashboard_network_devices'=>'post','dashboard_network_device'=>'patch','dashboard_network_rotate_device_token'=>'post','dashboard_network_retry_provisioning'=>'post','dashboard_network_verify_node'=>'post','dashboard_network_verify_dns'=>'post','dashboard_network_open_port'=>'post','dashboard_network_close_port'=>'post','dashboard_network_run_cron_job'=>'post','dashboard_network_toggle_cron_job'=>'post'}.each { |path, method| assert form_for(path,method), path }
    %w[post patch delete].each { |method| assert form_for('dashboard_network_cron_jobs',method), method }
  end
  def test_visible_controls_have_labels_and_section_links_resolve
    @doc.css('input:not([type=hidden]):not([type=submit]),select').each { |field| assert field.ancestors('label').any?, field['name'] }
    @doc.css('nav[aria-label="Network sections"] a').each { |link| assert @doc.at_css(link['href']), link['href'] }
    ids = @doc.css('[id]').map { |element| element['id'] }
    assert_equal ids.uniq, ids
  end
end
