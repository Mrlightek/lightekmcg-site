require_relative 'fleet_hosting_test'
require Rails.root.join('app/services/lightek_sessions/media_setup').to_s
GatekeeperProject.belongs_to :gatekeeper_node
class MediaSetupTest < FleetUpdatesTest
  FleetUpdatesTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_media_setup_registers_existing_central_runtime_without_enabling_fleet_updates
    owner=hosting_owner('super_admin');node,project=hosting_server(owner)
    node.update!(ip_address:'127.0.0.1',metadata:{'role'=>'production','local_node'=>true})
    site=OpenStruct.new(host:project.domain,tenant:owner)
    assert_equal 0,LightekSessions::MediaSetup.installations(site:site,actor:owner).count
    runtime=LightekSessions::MediaSetup.connect!(site:site,actor:owner,project_id:project.id)
    assert_equal project.id,runtime.gatekeeper_project_id
    assert_equal owner.id,runtime.account_id
    assert_equal project.domain,runtime.domain
    assert runtime.configured?
    refute runtime.eligible?
    again=LightekSessions::MediaSetup.connect!(site:site,actor:owner,project_id:project.id)
    assert_equal runtime.id,again.id
    assert_equal [runtime.id],LightekSessions::MediaSetup.installations(site:site,actor:owner).pluck(:id)
  end
  def test_media_setup_rejects_foreign_node_wrong_site_and_account_reassignment
    owner=hosting_owner;other=hosting_owner;node,project=hosting_server(owner)
    site=OpenStruct.new(host:project.domain,tenant:owner)
    assert_raises(ActiveRecord::RecordNotFound){LightekSessions::MediaSetup.connect!(site:site,actor:other,project_id:project.id)}
    wrong=OpenStruct.new(host:'wrong.example.com',tenant:owner)
    assert_raises(ActiveRecord::RecordNotFound){LightekSessions::MediaSetup.connect!(site:wrong,actor:owner,project_id:project.id)}
    runtime=LightekSessions::MediaSetup.connect!(site:site,actor:owner,project_id:project.id)
    runtime.update!(account:other)
    assert_raises(ArgumentError){LightekSessions::MediaSetup.connect!(site:site,actor:owner,project_id:project.id)}
    assert_equal other.id,runtime.reload.account_id
  end
  def test_media_setup_refuses_deleting_servers
    owner=hosting_owner;node,project=hosting_server(owner)
    node.update!(status:'deleting')
    site=OpenStruct.new(host:project.domain,tenant:owner)
    assert_raises(Gatekeeper::Hosting::Access::Denied){LightekSessions::MediaSetup.connect!(site:site,actor:owner,project_id:project.id)}
    refute GatekeeperInstallation.exists?(gatekeeper_project_id:project.id)
  end
end
