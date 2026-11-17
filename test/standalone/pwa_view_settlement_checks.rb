require_relative 'pwa_member_backend_checks'
require File.join(ROOT, 'db/migrate/20261117143000_create_pwa_view_settlements')
CreatePwaViewSettlements.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:lightek_pwa_youtube_uploads) { |t| t.integer :site_id; t.integer :user_id; t.string :video_id }
  create_table(:lightek_pwa_creator_earnings) { |t| t.integer :principal_cents; t.string :state }
  add_column :users, :stripe_connect_account_id, :string
end
User.reset_column_information
module LightekPwa
  class YoutubeUpload < ApplicationRecord
    self.table_name = 'lightek_pwa_youtube_uploads'
    belongs_to :site, class_name: 'DymondSite::Site'
  end
  class CreatorEarning < ApplicationRecord
    self.table_name = 'lightek_pwa_creator_earnings'
  end
end
%w[view_batch view_earning].each { |name| require File.join(ROOT, "app/models/lightek_pwa/#{name}") }
%w[view_reconciliation view_settlement].each { |name| require File.join(ROOT, "app/services/lightek_pwa/#{name}") }
module LightekPayments
  module PayoutAccounts
    def self.options = {}
    def self.status(user) = {state: 'ready'}
  end
end
module Stripe
  class Account; def self.retrieve(*) = {}; end
  class Topup; def self.retrieve(*) = {}; end
  class Balance; def self.retrieve(*) = {}; end
  class Transfer
    def self.create(*) = {}
    def self.list(*) = {'data'=>[], 'has_more'=>false}
    def self.retrieve(*) = {}
  end
end
class PwaViewSettlementTest < PwaCommercialTest
  PwaCommercialTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @previous_channel = ENV['LIGHTEK_YOUTUBE_CHANNEL_ID']; @previous_release = ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED']
    ENV['LIGHTEK_YOUTUBE_CHANNEL_ID'] = 'UC' + 'a'*22
    ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED'] = 'true'
    @owner.update!(stripe_connect_account_id: 'acct_creator')
    @month = 2.months.ago.to_date.beginning_of_month
    @video = 'abcdefghijk'
    LightekPwa::YoutubeUpload.create!(site_id: @site.id, user_id: @owner.id, video_id: @video)
    LightekPwa::RevenuePeriod.create!(purchase: @purchase, source_reference: 'historical-paid-month', starts_at: @month.in_time_zone('America/Los_Angeles'), ends_at: @month.next_month.in_time_zone('America/Los_Angeles'), creator_share_bps: 8000)
    @rows = "date,video_id,estimated_revenue_usd,views\n#{@month},#{@video},50.000000,1000\n#{@month},platform123,50.000000,2000\n"
    @funding = {'id'=>'tu_funding', 'status'=>'succeeded', 'currency'=>'usd', 'livemode'=>true,
      'balance_transaction'=>{'id'=>'txn_funding','source'=>'tu_funding','type'=>'topup','status'=>'available','currency'=>'usd','available_on'=>1.hour.ago.to_i,'net'=>10_000}}
    @account = {'id'=>'acct_platform','settings'=>{'payouts'=>{'schedule'=>{'interval'=>'manual'}}}}
  end
  def teardown
    ENV['LIGHTEK_YOUTUBE_CHANNEL_ID'] = @previous_channel
    ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED'] = @previous_release
    super
  end
  def reconcile(cents=8000, rows=@rows)
    LightekPwa::ViewReconciliation.call!(site: @site, actor: @operator, month: @month.iso8601, finalized_cents: cents,
      source_reference: 'AdSense monthly channel receipt', report: StringIO.new(rows), finalized_receipt: StringIO.new('actual finalized receipt'), complete_channel: true)
  end
  def fund(batch)
    Stripe::Account.stub(:retrieve, @account) do
      Stripe::Topup.stub(:retrieve, @funding) do
        LightekPwa::ViewSettlement.fund!(batch: batch, actor: @operator, reference: 'tu_funding')
      end
    end
  end
  def test_complete_channel_denominator_and_historical_eligibility_produce_final_earnings
    @subscription.update!(status: 'canceled')
    batch = reconcile
    assert_equal 3200, batch.creator_liability_cents # $80 finalized × 50% attributable × 80% creator
    row = batch.view_earnings.sole
    assert_equal 1000, row.views
    assert_equal 3200, row.amount_cents
    assert_equal 'awaiting_funding', row.state
    assert_equal 3200, row.earnings_per_thousand_views_cents
    assert_equal batch.id, reconcile.id
    assert_raises(ArgumentError) { reconcile(9000) }
    assert_equal 1, LightekPwa::ViewBatch.count
  end
  def test_free_days_contribute_to_channel_denominator_but_do_not_become_paid_earnings
    LightekPwa::RevenuePeriod.delete_all
    batch = reconcile
    assert_equal 0, batch.creator_liability_cents
    assert_empty batch.view_earnings
  end
  def test_duplicate_daily_rows_and_wrong_month_are_rejected
    duplicate = @rows + "#{@month},#{@video},1,10\n"
    assert_raises(ArgumentError) { reconcile(8000, duplicate) }
    assert_raises(ArgumentError) { reconcile(8000, @rows.sub(@month.iso8601, @month.prev_month.iso8601)) }
    assert_equal 0, LightekPwa::ViewBatch.count
  end
  def test_pending_reversed_underfunded_and_automatic_payout_funding_are_rejected
    batch = reconcile
    %w[pending reversed].each do |state|
      @funding['status'] = state
      assert_raises(LightekPwa::ViewSettlement::Unavailable) { fund(batch) }
    end
    @funding['status'] = 'succeeded'; @funding['balance_transaction']['net'] = 3199
    assert_raises(LightekPwa::ViewSettlement::Unavailable) { fund(batch) }
    @funding['balance_transaction']['net'] = 10000; @account['settings']['payouts']['schedule']['interval'] = 'daily'
    assert_raises(LightekPwa::ViewSettlement::Unavailable) { fund(batch) }
    assert_nil batch.reload.funding_reference
  end
  def test_verified_funding_and_exactly_once_transfer_recover_a_lost_response
    batch = fund(reconcile); row = batch.view_earnings.sole
    assert_equal 'available', row.state
    receipt = nil; calls = 0
    create = lambda do |payload, options|
      calls += 1
      receipt = payload.deep_stringify_keys.merge('id'=>'tr_view', 'amount_reversed'=>0)
      raise IOError, 'response lost after provider accepted'
    end
    Stripe::Account.stub(:retrieve, @account) do
      Stripe::Topup.stub(:retrieve, @funding) do
        Stripe::Balance.stub(:retrieve, {'available'=>[{'currency'=>'usd','amount'=>10_000}]}) do
          Stripe::Transfer.stub(:create, create) do
            assert_raises(IOError) { LightekPwa::ViewSettlement.release!(earning: row, actor: @owner) }
          end
          assert_equal 'transfer_pending', row.reload.state
          assert_equal 'acct_creator', row.destination_account
          Stripe::Transfer.stub(:list, {'data'=>[receipt], 'has_more'=>false}) do
            LightekPwa::ViewSettlement.release!(earning: row, actor: @owner)
          end
        end
      end
    end
    assert_equal 1, calls
    assert_equal 'transferred', row.reload.state
    assert_equal 'tr_view', row.transfer_reference
  end
  def test_old_uncertain_transfer_cannot_be_blindly_reposted
    row = fund(reconcile).view_earnings.sole
    row.update!(state: 'transfer_pending', destination_account: 'acct_creator', transfer_requested_at: 2.days.ago)
    assert_raises(LightekPwa::ViewSettlement::Unavailable) { LightekPwa::ViewSettlement.recover_transfer(row) }
    assert_nil row.reload.transfer_reference
  end
  def test_release_cannot_consume_gift_principal_or_change_destinations
    row = fund(reconcile).view_earnings.sole
    LightekPwa::CreatorEarning.create!(state: 'available', principal_cents: 9000)
    Stripe::Account.stub(:retrieve, @account) do
      Stripe::Topup.stub(:retrieve, @funding) do
        Stripe::Balance.stub(:retrieve, {'available'=>[{'currency'=>'usd','amount'=>10000}]}) do
          assert_raises(LightekPwa::ViewSettlement::Unavailable) { LightekPwa::ViewSettlement.release!(earning: row, actor: @owner) }
        end
      end
    end
    assert_equal 'available', row.reload.state
    assert_nil row.destination_account
    assert_raises(LightekPwa::ViewSettlement::Unavailable) { LightekPwa::ViewSettlement.release!(earning: row, actor: @operator) }
  end
end
