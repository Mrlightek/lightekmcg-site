require_relative 'pwa_youtube_publishing_checks'
require File.join(ROOT,'db/migrate/20261117110000_create_pwa_creator_payments')
CreatePwaCreatorPayments.new.migrate(:up)
module Stripe
  class StripeError < StandardError; end
end
%w[app/models/lightek_pwa/creator_offer app/models/lightek_pwa/creator_payment app/models/lightek_pwa/creator_earning
 app/services/lightek_commerce/merchant_payouts app/services/lightek_commerce/stripe_checkout app/services/lightek_payments/payout_accounts
 app/services/lightek_pwa/creator_support app/services/lightek_pwa/creator_settlement app/controllers/api/pwa_creator_support_controller app/controllers/api/pwa_youtube_controller].each { |f|require File.join(ROOT,f) }
Rails.application.routes.append do
 get '/api/lightek/pwa/creators/:profile_id',to:'api/pwa_creator_support#show'
 post '/api/lightek/pwa/creators/:profile_id/configure',to:'api/pwa_creator_support#configure'
 post '/api/lightek/pwa/creators/:profile_id/quote',to:'api/pwa_creator_support#quote'
 get '/api/lightek/pwa/youtube/source',to:'api/pwa_youtube#source'
 get '/api/lightek/pwa/youtube/posts/:post_id',to:'api/pwa_youtube#show'
 post '/api/lightek/pwa/youtube/posts/:post_id',to:'api/pwa_youtube#create'
end
Rails.application.reload_routes!
class PwaCommercialHttpTest < PwaCommercialTest
 PwaCommercialTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
 def client
   @client ||= ActionDispatch::Integration::Session.new(Rails.application).tap { |c|c.host! @site.host }
 end
 def headers(user=@owner) = {'X-Pwa-Test-User'=>user.id.to_s,'Accept'=>'application/json'}
 def json = JSON.parse(client.response.body)
 def csrf(user=@owner)
   client.get '/test/csrf',headers:headers(user)
   assert_equal 200,client.response.status
   headers(user).merge('X-CSRF-Token'=>json.fetch('csrf_token'))
 end
 def path = "/api/lightek/pwa/creators/#{@owner.profile.id}"
 def test_anonymous_members_can_read_offer_but_cannot_change_it
   client.get path
   assert_equal 200,client.response.status
   assert_equal false,json['enabled']
   client.post path+'/configure',params:{monthly_cents:500,enabled:true},as: :json
   assert_equal 401,client.response.status
   assert_empty LightekPwa::CreatorOffer.all
 end
 def test_csrf_and_ownership_are_enforced_on_creator_offer_changes
   previous=ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED'];ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']='true'
   client.post path+'/configure',headers:headers,params:{monthly_cents:500,enabled:true},as: :json
   assert_equal 422,client.response.status
   client.post path+'/configure',headers:csrf(@operator),params:{monthly_cents:500,enabled:true},as: :json
   assert_equal 403,client.response.status
   client.post path+'/configure',headers:csrf,params:{monthly_cents:500,enabled:true},as: :json
   assert_equal 200,client.response.status,client.response.body
   assert_equal @owner.id,LightekPwa::CreatorOffer.last.creator_id
 ensure
   previous ? ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']=previous : ENV.delete('LIGHTEK_CREATOR_SUPPORT_ENABLED')
 end
 def test_quote_returns_full_principal_and_disclosed_fee_without_creating_payment
   previous=ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED'];ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']='true'
   LightekPwa::CreatorOffer.create!(site:@site,creator:@owner,enabled:true,monthly_cents:500)
   client.post path+'/quote',headers:csrf(@operator),params:{kind:'tip',principal_cents:500,creator_id:@operator.id},as: :json
   assert_equal 200,client.response.status,client.response.body
   assert_equal 500,json['principal_cents']
   assert_equal @owner.id,json['creator_id']
   assert_operator json['fee_cents'],:>,0
   assert_empty LightekPwa::CreatorPayment.all
 ensure
   previous ? ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']=previous : ENV.delete('LIGHTEK_CREATOR_SUPPORT_ENABLED')
 end
 def test_original_source_requires_expiring_grant_and_never_uses_source_session
   client.get '/api/lightek/pwa/youtube/source',params:{grant:'forged'},headers:headers(@operator)
   assert_equal 403,client.response.status
 end
 def test_revenue_administration_renders_missing_launch_gaps_without_sales_control
   view=ActionView::Base.with_empty_template_cache.with_view_paths(File.join(ROOT,'app/views'))
   view.assign(shared_pools:[],member_backends:[],pool_packages:[],view_batches:[],site:@site,launch_readiness:{launch_candidate:false,paid_sales_ready:false,implementation_gaps:{migration:'Verified migration missing'},configuration:{payments:false},production_acceptance:{billing:'Real payment acceptance pending'}},
     membership:{enabled:false,setup_note:'Test setup'},packages:[],purchases:[],youtube_uploads:[],creator_earnings:[],receipts:[],learning_build:nil)
   %i[routing_dashboard_pwa_revenue_path pools_dashboard_pwa_revenue_path finalize_views_dashboard_pwa_revenue_path dashboard_pwa_path import_dashboard_pwa_revenue_path prepare_nevaeh_dashboard_pwa_revenue_path].each { |name|view.define_singleton_method(name) { |**| '/dashboard/pwa/revenue' } }
   view.define_singleton_method(:flash) { {} }
   view.define_singleton_method(:protect_against_forgery?) { false }
   html=view.render(template:'dashboard/pwa_revenue/show')
   assert_includes html,'Verified migration missing'
   assert_includes html,'Channel publishing'
   refute_includes html,'Open paid membership'
 end
 def test_youtube_status_cannot_read_another_users_private_source
   p=Post.create!(user:@owner,site:@site,title:'Private original',kind:'video',visibility:'private',audience:'everyone')
   client.get "/api/lightek/pwa/youtube/posts/#{p.id}",headers:headers(@operator)
   assert_equal 404,client.response.status
   client.get "/api/lightek/pwa/youtube/posts/#{p.id}",headers:headers
   assert_equal 200,client.response.status
   assert_nil json['upload']
   assert_equal 'private, no-store',client.response.headers['Cache-Control']
 end
end
