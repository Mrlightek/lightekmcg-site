require 'test_helper'

class LightekTeam::NetworkTest < ActiveSupport::TestCase
  setup do
    @host = build_peer
    @partner = build_peer
    @unrelated = build_peer
  end

  test 'peer identity scopes invitations, membership, posting, and disconnect' do
    host = service(@host)
    partner = service(@partner)
    outsider = service(@unrelated)
    employee = service(@partner, 'user-7')
    key = host.create!(name: 'network-screening', address: @partner.site.host).fetch(:key)

    assert_equal 'invited', partner.show(key).fetch(:status)
    assert_raises(ActiveRecord::RecordNotFound) { outsider.show(key) }
    assert_raises(ActiveRecord::RecordNotFound) { employee.show(key) }
    assert_equal 'connected', partner.accept!(key).fetch(:status)

    partner.member!(key, subject: 'user-7', display_name: 'Guest producer', remove: false)
    assert_includes employee.show(key).fetch(:participants).pluck(:name), 'Guest producer'
    request = SecureRandom.uuid
    2.times { employee.post!(key, body: 'Screening is ready', request_key: request) }
    assert_equal [@partner.site.host], host.show(key).fetch(:messages).pluck(:organization)

    partner.disconnect!(key)
    assert_raises(ActiveRecord::RecordNotFound) { employee.show(key) }
    assert_raises(ActiveRecord::RecordNotFound) { partner.show(key) }
    assert_equal 'disconnected', host.show(key).fetch(:status)
  end

  test 'installation mail is unique, survives provisioning retries, and has an isolated inbox' do
    admin = account('super_admin')
    LightekMail::Domain.find_or_create_by!(name: LightekEmailProvisioningService::DOMAIN) do |domain|
      domain.assign_attributes(user: admin, verified_at: Time.current)
    end
    service = LightekMail::InstallationMailbox.new(@host)
    mailbox = service.provision!
    other = LightekMail::InstallationMailbox.new(@partner)
    assert_equal mailbox.id, service.provision!.id
    partner_mailbox = other.provision!
    refute_equal mailbox.address, partner_mailbox.address
    invited = service(@host).create!(name: 'mailbox-invitation', address: partner_mailbox.address)
    assert_equal 'invited', service(@partner).show(invited.fetch(:key)).fetch(:status)

    message = mailbox.messages.create!(direction: 'inbound', state: 'inbox', from_address: 'partner@example.test',
      message_id: SecureRandom.uuid, subject: 'Studio booking', text_body: 'Confirmed.')
    assert_equal [message.id], service.inbox('inbox').fetch(:messages).pluck(:id)
    assert_raises(ActiveRecord::RecordNotFound) { other.read(message.id) }
    assert_equal 'Confirmed.', service.read(message.id).fetch(:text)
  end

  test 'network office edits share one revision and disconnect removes partner access' do
    host = service(@host)
    partner = service(@partner)
    key = host.create!(name: 'office', address: @partner.site.host).fetch(:key)
    assert_raises(ArgumentError) { host.office!(key, 'list', {}) }
    partner.accept!(key)
    fields = {'file_key'=>SecureRandom.hex(16), 'title'=>'Budget', 'kind'=>'spreadsheet', 'content'=>'1,2,=SUM(A1:B1)'}
    file = host.office!(key, 'create', fields)
    assert_equal file, host.office!(key, 'create', fields)
    assert_equal file, partner.office!(key, 'show', fields).except(:content)
    partner.office!(key, 'update', fields.merge('lock_version'=>0, 'content'=>'2,3,=SUM(A1:B1)'))
    assert_raises(ArgumentError) { host.office!(key, 'update', fields.merge('lock_version'=>0)) }
    assert_raises(ActiveRecord::RecordNotFound) { service(@unrelated).office!(key, 'show', fields) }
    partner.disconnect!(key)
    assert_raises(ActiveRecord::RecordNotFound) { partner.office!(key, 'show', fields) }
    assert_equal '2,3,=SUM(A1:B1)', host.office!(key, 'show', fields).fetch(:content)
    assert_raises(ArgumentError) { host.office!(key, 'update', fields.merge('lock_version'=>1)) }
  end

  private

  def account(role)
    User.create!(first_name: 'Network', last_name: 'Test', email_address: "network-#{SecureRandom.hex(7)}@example.test",
      password: 'Network-installation-test-password!', role: role)
  end

  def build_peer
    merchant = account('client')
    site = DymondSite::Site.create!(name: 'Network installation', host: "install-#{SecureRandom.hex(7)}.example.test", tenant: merchant)
    order = LightekCommerce::Order.create!(site: site, customer_email: merchant.email_address, status: 'fulfilled',
      paid_at: Time.current, provisioned_at: Time.current)
    key = SecureRandom.uuid
    token = "#{key}.#{SecureRandom.hex(32)}"
    LightekReservations::Peer.create!(order: order, site: site, merchant: merchant, key: key, enabled: true,
      token_digest: Digest::SHA256.hexdigest(token))
  end

  def service(peer, subject = 'owner')
    LightekTeam::Network.new(peer: peer, subject: subject, actor_name: 'Guest producer')
  end
end
