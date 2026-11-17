require_relative 'pwa_commercial_checks'
require File.join(ROOT,'app/services/lightek_pwa/business_activation')
module DymondBank
  module StripeCredentials
    def self.secret_key = nil
  end
end
module LightekPwa
  class CreatorSupport
    def self.enabled?(*) = false
  end
  class SharedPool
    def self.where(*) = []
  end
end
ActiveRecord::Schema.define do
  add_column :users, :agency_id, :integer
  create_table(:agency_profiles) { |t| t.integer :user_id; t.string :brand_name; t.string :accent_color, default:'#d4af37'; t.string :logo_url; t.string :support_email }
end
class User
  belongs_to :agency, class_name:'User',optional:true
  has_one :agency_profile
end
require File.join(ROOT,'app/models/agency_profile')
class PwaLaunchGateTest < PwaCommercialTest
  PwaCommercialTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def test_missing_separate_host_and_configuration_cannot_be_overridden_by_enabled_flag
    @site.update!(manifest:{'pwa_commerce'=>{'enabled'=>true}})
    refute LightekPwa::Plans.enabled?(@site)
    error=assert_raises(LightekPwa::Plans::Unavailable) {LightekPwa::Plans.install!(site:@site,actor:@operator,personal_product_id:1)}
    assert_includes error.message,'configuration'
    assert @purchase.entitled?, 'Existing verified paid periods must be preserved'
  end
  def test_business_role_and_branding_activate_only_after_verified_payment
    @purchase.update!(plan_key:'business')
    @order.update!(paid_at:nil,status:'pending_payment')
    LightekPwa::BusinessActivation.call!(order:@order)
    assert_equal 'client',@owner.reload.role
    assert_nil @owner.agency_profile
    @order.update!(paid_at:Time.current,status:'paid')
    2.times {LightekPwa::BusinessActivation.call!(order:@order)}
    assert_equal 'white_label',@owner.reload.role
    assert_equal @operator,@owner.agency
    assert_equal 'Creator',@owner.agency_profile.brand_name
    assert_equal 1,AgencyProfile.count
  end
  def test_payment_does_not_change_an_employees_privileged_directory_role
    @purchase.update!(plan_key:'business');@owner.update!(role:'employee')
    assert_raises(LightekPwa::Plans::Unavailable) {LightekPwa::BusinessActivation.call!(order:@order)}
    assert_equal 'employee',@owner.reload.role
    assert_nil @owner.agency_profile
  end
  def test_personal_purchase_never_grants_agency_management
    LightekPwa::BusinessActivation.call!(order:@order)
    assert_equal 'client',@owner.reload.role
    assert_nil @owner.agency_profile
  end
end
