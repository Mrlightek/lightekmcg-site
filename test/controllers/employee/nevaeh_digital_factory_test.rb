# frozen_string_literal: true
require 'test_helper'
class NevaehDigitalFactoryHttpTest < ActionDispatch::IntegrationTest
  PASSWORD='nevaeh-factory-http-tests'
  def sign_in(role)
    @user=User.create!(email_address:"factory-#{SecureRandom.hex(5)}@example.test",first_name:'Factory',last_name:'Operator',role:role,password:PASSWORD)
    post session_path,params:{email_address:@user.email_address,password:PASSWORD}
    assert_response :redirect
  end
  test 'internal library and help require administrator access' do
    get employee_software_library_path
    refute response.successful?
    get employee_nevaeh_help_path(topic:'training')
    refute response.successful?
    sign_in('employee')
    get employee_software_library_path
    refute response.successful?
    get employee_nevaeh_factory_path
    refute response.successful?
  end
  test 'administrator can read installed documentation and contextual field help' do
    sign_in('super_admin')
    get employee_software_library_path,params:{q:'Nevaeh'}
    assert_response :success
    assert_select '.sl-results'
    assert_equal 'private, no-store',response.headers['Cache-Control']
    get employee_nevaeh_help_path(topic:'training'),params:{field:'Training epochs'},as: :json
    assert_response :success
    assert_includes response.parsed_body['body'],'epoch'
    get employee_nevaeh_help_path(topic:'unknown'),as: :json
    assert_response :not_found
  end
  test 'construction build emits implemented Ruby and sample evidence' do
    sign_in('super_admin')
    definition={input_schema:{name:'string'},steps:[{op:'template',field:'greeting',text:'Hello {name}'}]}
    samples=[{inputs:{name:'Marlon'},expected:{name:'Marlon',greeting:'Hello Marlon'}}]
    post employee_nevaeh_factory_constructions_path,params:{construction:{name:'Greeting',key:"greeting_#{SecureRandom.hex(5)}"},definition_json:definition.to_json,tests_json:samples.to_json}
    assert_response :redirect
    record=NevaehConstruction.order(:id).last
    post employee_nevaeh_factory_build_construction_path(record)
    assert_response :redirect
    release=record.releases.last
    assert_equal 'verified',release.status
    get employee_nevaeh_factory_release_artifacts_path(release)
    assert_response :success
    assert_includes response.body,'def self.call'
    refute_includes response.body,'NotImplementedError'
  end
  test 'synthetic datasets remain draft until explicit review approval' do
    sign_in('super_admin')
    post employee_nevaeh_factory_generate_dataset_path,params:{topic:'Studio',count:10,name:'Studio test conversations'}
    assert_response :redirect
    dataset=NevaehTrainingDataset.order(:id).last
    assert_equal 'draft',dataset.status
    assert_equal 10,dataset.examples.length
    post employee_nevaeh_factory_approve_dataset_path(dataset)
    assert_response :redirect
    assert_equal 'approved',dataset.reload.status
    get employee_nevaeh_factory_path(tab:'training',dataset_id:dataset.id)
    assert_response :success
    assert_select 'textarea[name=examples_json]'
  end
end
