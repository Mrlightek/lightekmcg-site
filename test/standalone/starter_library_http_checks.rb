require_relative 'starter_library_checks'
require 'rails'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'

class StarterHttpFixture < Rails::Application
  config.root=Dir.mktmpdir('starter-http')
  config.eager_load=false
  config.secret_key_base='standalone-starter-fixture-'*4
  config.hosts.clear
  config.logger=Logger.new(File::NULL)
  config.action_dispatch.show_exceptions=:none
  config.action_controller.allow_forgery_protection=true
  config.cache_store=:memory_store
end
StarterHttpFixture.initialize!
def Rails.root = Pathname.new(File.expand_path('../..', __dir__))
class ApplicationController < ActionController::Base
  def self.allow_unauthenticated_access(**); end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
end
class StarterTokenController < ApplicationController
  protect_from_forgery with: :exception
  def show = render(json:{token:form_authenticity_token})
end
require_relative '../../app/controllers/website_template_inquiries_controller'
ActiveRecord::Base.connection.rename_table(:sections,:dymond_site_sections)
DymondSite::Section.table_name='dymond_site_sections'
Rails.application.routes.draw do
  get '/token',to:'starter_token#show'
  post '/website/template-inquiries',to:'website_template_inquiries#create'
end
class StarterLibraryHttpChecks < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.clear
    WebsiteTemplateInquiry.delete_all
    DymondSite::Section.delete_all;DymondSite::Page.delete_all;DymondSite::Site.delete_all
    @site=DymondSite::Site.create!(name:'Client',host:'client.example.test',manifest:{})
    @page=@site.pages.create!(title:'Contact',slug:'contact',published:true)
    @page.sections.create!(kind:'starter_barber_clean_cut_contact',data:{'template_key'=>'barber-clean-cut','section_key'=>'contact'})
    host! @site.host
    get '/token';@token=response.parsed_body.fetch('token')
  end
  def payload = {template_key:'barber-clean-cut',section_key:'contact',name:'A visitor',phone:'555-0100',authenticity_token:@token}
  def test_valid_same_host_request_is_persisted
    post '/website/template-inquiries',params:payload,as: :json
    assert_response :created
    assert_equal 1,WebsiteTemplateInquiry.count
    assert_equal @site.id,WebsiteTemplateInquiry.last.site_id
    assert_includes response.parsed_body['message'],'received'
  end
  def test_json_submission_without_csrf_is_rejected
    assert_raises(ActionController::InvalidAuthenticityToken){post '/website/template-inquiries',params:payload.except(:authenticity_token),as: :json}
    assert_equal 0,WebsiteTemplateInquiry.count
  end
  def test_unpublished_source_is_not_a_public_form
    @page.update!(published:false)
    post '/website/template-inquiries',params:payload,as: :json
    assert_response :not_found
    assert_equal 0,WebsiteTemplateInquiry.count
  end
  def test_unknown_host_cannot_select_a_foreign_site_by_id
    host! 'other.example.test'
    get '/token';@token=response.parsed_body.fetch('token')
    post '/website/template-inquiries',params:payload.merge(site_id:@site.id),as: :json
    assert_response :not_found
    assert_equal 0,WebsiteTemplateInquiry.count
  end
  def test_required_fields_return_an_error_and_never_a_success
    post '/website/template-inquiries',params:payload.merge(phone:''),as: :json
    assert_response :unprocessable_entity
    assert_equal 0,WebsiteTemplateInquiry.count
    assert response.parsed_body.key?('error')
  end
  def test_repeated_requests_are_rate_limited
    10.times{post '/website/template-inquiries',params:payload,as: :json;assert_response :created}
    post '/website/template-inquiries',params:payload,as: :json
    assert_response :too_many_requests
    assert_equal 10,WebsiteTemplateInquiry.count
  end
end
