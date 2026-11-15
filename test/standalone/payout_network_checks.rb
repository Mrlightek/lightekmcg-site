require_relative 'commerce_hosting_test'
require Rails.root.join('app/services/lightek_reservations/federation/client').to_s
require Rails.root.join('app/models/lightek_commerce/payout_schedule').to_s
ActiveRecord::Schema.define do
  add_column :users, :stripe_connect_details_submitted, :boolean, default: false
  add_column :users, :stripe_connect_payouts_enabled, :boolean, default: false
  create_table(:lightek_merchant_payout_schedules) do |t|
    t.references :merchant; t.string :cadence, default: 'biweekly'; t.boolean :enabled, default: true; t.datetime :next_run_at
  end
end
class PayoutNetworkChecks < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_personal_payout_setup_resolves_the_signed_in_descendant_before_central_sign_in
    client=User.create!(agency:@operator,role:'client',email_address:'personal@example.test')
    prior=ENV['LIGHTEK_DEPLOYED_SITE_HOST']
    ENV['LIGHTEK_DEPLOYED_SITE_HOST']=@site.host
    config={'origin'=>'https://central.example.test','credential_slug'=>'test','key'=>'peer-test'}
    body=nil
    LightekReservations::Federation::Client.stub(:config,config) do
      connection=LightekReservations::Federation::Client.new(@site)
      connection.define_singleton_method(:request) { |_,**args| body=args.fetch(:body); {} }
      connection.ensure_payout_identity!(merchant:client)
    end
    assert_equal [@operator.email_address,client.email_address],body[:merchant_chain].map { |row| row['email'] }
    refute body.key?(:account_id)
    refute body.key?(:client_secret)
  ensure
    prior ? ENV['LIGHTEK_DEPLOYED_SITE_HOST']=prior : ENV.delete('LIGHTEK_DEPLOYED_SITE_HOST')
  end
  def test_downstream_status_resolves_the_actual_merchant_chain_not_the_peer_owner
    agency=User.create!(agency:@operator,role:'white_label',email_address:'agency@example.test')
    client=User.create!(agency:agency,role:'client',email_address:'client@example.test')
    site=DymondSite::Site.create!(tenant:client,name:'Client store',host:'client.example.test')
    @operator.update!(stripe_connect_account_id:'acct_platform')
    config={'origin'=>'https://central.example.test','credential_slug'=>'test','key'=>'peer-test'}
    calls=[]
    LightekReservations::Federation::Client.stub(:config,config) do
      connection=LightekReservations::Federation::Client.new(site)
      connection.define_singleton_method(:request) do |path,**args|
        calls << [path,args]
        {'connect_account_id'=>'acct_actual_client','connect_details_submitted'=>true,'connect_payouts_enabled'=>false,
          'cadence'=>'weekly','enabled'=>true,'next_run_at'=>Time.current.iso8601}
      end
      connection.synchronize_payouts!(merchant:client)
      assert_raises(LightekReservations::Federation::Client::Unavailable) {connection.synchronize_payouts!(merchant:@operator)}
    end
    assert_equal 'commerce/summary',calls.first.first
    assert_equal :post,calls.first.last[:method]
    chain=calls.first.last[:body][:merchant_chain]
    assert_equal [@operator.email_address,agency.email_address,client.email_address],chain.map { |row| row['email'] }
    assert_equal 'acct_actual_client',client.reload.stripe_connect_account_id
    refute client.stripe_connect_payouts_enabled?
    assert_equal 'acct_platform',@operator.reload.stripe_connect_account_id
    assert_equal 'weekly',LightekCommerce::PayoutSchedule.find_by!(merchant:client).cadence
    refute LightekCommerce::PayoutSchedule.exists?(merchant:@operator)
  end
end
