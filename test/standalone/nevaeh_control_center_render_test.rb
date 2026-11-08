# frozen_string_literal: true
# Real ActionView templates rendered with controlled route/auth adapters.
require_relative "nevaeh_control_center_test"
require "action_view"
require "ostruct"
require File.join(ROOT, "app/helpers/nevaeh_control_center_helper")
module LightekPwa
  class Policy
    def self.administration_available_for?(*) = true
  end
end
class NevaehControlCenterRenderTest < Minitest::Test
  def teardown
    [NevaehWorkflowRun, NevaehWorkflow, NevaehWritingProfile, NevaehInferenceModel, NevaehWorkspacePreference].each(&:delete_all)
  end
  def test_all_six_tabs_render_with_live_models
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT,'app/views')]),{},nil)
    view.extend(NevaehControlCenterHelper)
    class << view
      def current_user = @preview_user
      def can?(*args) = true
      def main_app = self
      def dymond_dash = self
      def protect_against_forgery? = false
      def request = OpenStruct.new(path: '/employee/nevaeh/control-center')
      def params = {}
      def url_for(value) = value.is_a?(String) ? value : '/preview'
      def method_missing(name,*args,**kwargs,&block)
        return '/employee/nevaeh/control-center' if name == :employee_nevaeh_control_center_path
        return '/dashboard' if name == :root_path
        return '/'+name.to_s.sub(/_path$/,'').tr('_','/') if name.to_s.end_with?('_path')
        super
      end
      def respond_to_missing?(name,*args) = name.to_s.end_with?('_path') || super
    end
    admin=User.create!(role:'super_admin')
    def admin.email_address = 'operator@example.test'
    view.instance_variable_set(:@preview_user,admin)
    model=NevaehInferenceModel.create!(name:'Studio Voice',rules:[{'id'=>'premiere','format'=>'script','keywords'=>['studio','premiere'],'weight'=>1,'templates'=>['INT. {setting} — DAY','{protagonist}: We need to {goal}.','{companion}: First, we deal with {obstacle}.']}])
    profile=NevaehWritingProfile.create!(name:'Scene Director',format:'script',provider:'inference',inference_model:model)
    workflow=NevaehWorkflow.create!(creator:admin,name:'Opening night production',status:'active',interval_minutes:60,sections:[{'id'=>'project','action'=>'studio.project.create','inputs'=>{'name'=>'Opening night'},'depends_on'=>[]}])
    view.instance_variable_set(:@workflow,workflow)
    view.instance_variable_set(:@workflows,[workflow])
    view.instance_variable_set(:@runtime_capabilities,NevaehCapability.limit(5))
    view.instance_variable_set(:@runs,[])
    view.instance_variable_set(:@profiles,[profile])
    view.instance_variable_set(:@profile,profile)
    view.instance_variable_set(:@inference_models,[model])
    view.instance_variable_set(:@inference_model,model)
    %w[workers capabilities runs writing models navigation].each do |tab|
      view.instance_variable_set(:@tab, tab)
      html = view.render(template: "employee/nevaeh_control_center/index")
      assert_includes html, 'data-nevaeh-center'
      assert_includes html, 'Build her brilliance'
      refute_includes html, 'local_llm'
    end
  end
end
