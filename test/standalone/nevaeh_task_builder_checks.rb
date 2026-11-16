# Real SQLite, policy, Dispatch, worker and durable journal integration.
require_relative 'nevaeh_ten_task_checks'
require File.join(ROOT, 'db/migrate/20261114230000_create_nevaeh_manual_learning')
require File.join(ROOT, 'db/migrate/20261116110000_add_nevaeh_task_builder')
CreateNevaehManualLearning.new.migrate(:up)
AddNevaehTaskBuilder.new.migrate(:up)
%w[models/nevaeh_manual_build models/nevaeh_language_binding services/nevaeh_os/language_contract services/nevaeh_os/language services/nevaeh_os/task_builder].each { |file| require File.join(ROOT, 'app', file) }
module TaskBuilderCleanup
  def setup
    NevaehLanguageBinding.delete_all
    super
  end
end

NevaehOsTest.prepend(TaskBuilderCleanup)
class NevaehTaskBuilderChecks < NevaehTenTaskChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def setup
    super
    @actor.update!(role: 'super_admin')
    @doc = NevaehIntelligences::SoftwareLibrary.new.documents.find { |row| row[:path] == 'docs/nevaeh/tutorials/ten_tasks.md' }
    @website_worker = NevaehOsAgent.find_by!(user: @actor, system_key: 'website')
  end
  def attributes
    {'name'=>'My service page', 'template_key'=>'website_page', 'worker_id'=>@website_worker.id,
      'fixed'=>{'site_id'=>@site.id.to_s}, 'patterns'=>"prepare my service page called {title}\ncreate a page called {title}",
      'sample_phrase'=>'prepare my service page called About us', 'expected'=>{'title'=>'About us', 'site_id'=>''}}
  end
  def draft(values = attributes, **extra)
    NevaehOs::TaskBuilder.save!(actor: @actor, attributes: values, document_id: @doc[:id], **extra)
  end
  def publish(binding)
    NevaehOs::TaskBuilder.verify!(binding: binding, actor: @actor)
    NevaehOs::TaskBuilder.activate!(binding: binding, actor: @actor)
  end
  def test_example_verification_does_not_execute_and_activated_phrase_produces_real_report
    binding = draft
    assert_equal 'draft', binding.status
    assert_raises(ArgumentError) { NevaehOs::TaskBuilder.activate!(binding: binding, actor: @actor) }
    publish(binding)
    assert_empty NevaehOsAction.all
    assert_empty DymondSite::Page.all
    assert_equal false, binding.builder_verification['executed']
    result = ask('prepare my service page called Our services')
    action = NevaehOsAction.find(result.fetch('action_id'))
    assert_equal @website_worker.id.to_s, action.command['agent_ref']
    assert_equal binding.id, action.command.dig('command', 'language_binding', 'id')
    run = complete(result)
    dependency = NevaehOs::WorkerReports.dependency_for!(actor: @actor, run: run)
    report = NevaehOs::WorkerReports.resolve!(actor: @actor, dependency: dependency)
    assert_equal 'accepted', dependency['status']
    assert_equal 'completed', report['status']
    assert_equal 'Our services', @site.pages.sole.title
    assert_equal @site.id, action.command.dig('command', 'site_id')
  end
  def test_builder_phrase_precedes_generic_task_detection_and_missing_inputs_use_existing_form
    binding = draft; publish(binding)
    # This wording would otherwise enter the ten-task dialogue and ignore fixed inputs.
    result = ask('create a page called Custom title')
    assert_equal binding.id, NevaehOsAction.find(result['action_id']).command.dig('command', 'language_binding', 'id')
    start = ask('prepare my service page called', key: 'builder-input-start')
    assert_equal 'needs_clarification', start['status']
    assert_equal({'title'=>'string'}, start.dig('language_request', 'slots'))
    reply = ask('Complete the task', binding_id: binding.id, binding_fingerprint: binding.fingerprint, language_slots: {'title'=>'Filled form'})
    assert_equal @website_worker.id.to_s, NevaehOsAction.find(reply['action_id']).command['agent_ref']
    assert_equal 'planned', ask('prepare my service page called Preview', mode: 'reflect')['status']
  end
  def test_mismatched_example_or_worker_or_missing_executor_blocks_without_dispatch
    wrong = draft(attributes.merge('expected'=>{'title'=>'Different'}))
    assert_raises(ArgumentError) { publish(wrong) }
    refute wrong.reload.builder_verification['passed']
    sage = NevaehOsAgent.find_by!(user: @actor, system_key: 'sage')
    assert_includes NevaehOs::TaskBuilder.eligible_workers(@actor, 'website_page'), @website_worker
    refute_includes NevaehOs::TaskBuilder.eligible_workers(@actor, 'website_page'), sage
    assert_raises(ArgumentError) { draft(attributes.merge('worker_id'=>sage.id)) }
    assert_raises(ArgumentError) { draft(attributes.merge('template_key'=>'invented.adapter')) }
    assert_raises(ArgumentError) { draft({}) }
    assert_empty NevaehOsAction.all
  end
  def test_new_revision_is_independent_and_activation_pauses_prior_queued_binding
    old = draft; publish(old)
    queued = ask('prepare my service page called Queued')
    replacement = draft(attributes.merge('patterns'=>'replacement page {title}', 'sample_phrase'=>'replacement page About us'), previous_id: old.id)
    assert_equal 'active', old.reload.status
    assert_equal 2, replacement.builder_spec['version']
    assert_equal old.id, replacement.builder_spec['parent_id']
    assert_raises(ArgumentError) { NevaehOs::TaskBuilder.activate!(binding: replacement, actor: @actor) }
    publish(replacement)
    assert_equal 'paused', old.reload.status
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(NevaehOsAction.find(queued['action_id'])) }
    assert_empty DymondSite::Page.all
    assert_equal 'active', replacement.reload.status
  end
  def test_account_isolation_worker_revocation_and_source_tampering_block
    binding = draft; publish(binding)
    @other.update!(role: 'super_admin')
    assert_empty NevaehOs::TaskBuilder.scope(@other)
    assert_nil NevaehOs::Language.resolve('prepare my service page called Mine', actor: @other)
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::TaskBuilder.save!(actor: @other, attributes: attributes, document_id: @doc[:id], previous_id: binding.id) }
    checked = binding.command_template.merge('values'=>{'title'=>'Forgery'}, 'site_id'=>@site.id,
      'language_binding'=>{'id'=>binding.id, 'fingerprint'=>binding.fingerprint}, 'agent_id'=>@website_worker.id)
    assert_raises(ArgumentError) { NevaehOs::Language.guard!(checked, actor: @other) }
    @website_worker.update!(allowed_capabilities: ['sales.*'])
    assert_raises(ArgumentError) { NevaehOs::Language.guard!(checked, actor: @actor) }
    @website_worker.update!(allowed_capabilities: ['site.*'])
    binding.source_refs.first['sha256'] = '0' * 64
    binding.save!
    assert_equal 'draft', binding.status
    assert_raises(ArgumentError) { publish(binding) }
  end
  def test_fixed_site_cannot_be_changed_and_schedule_keeps_selected_worker
    binding = draft; publish(binding)
    command = NevaehOs::Language.resolve('prepare my service page called Safe', actor: @actor)['command']
    assert_raises(ArgumentError) { NevaehOs::Language.guard!(command.merge('site_id'=>@foreign.id, 'agent_id'=>@website_worker.id), actor: @actor) }
    result = ask('every 60 minutes, prepare my service page called Scheduled')
    action = NevaehOsAction.find(result.fetch('action_id'))
    assert_equal @website_worker.id.to_s, action.command['agent_ref']
    assert_equal 60, action.command['interval_minutes']
    receipt = execute(action)
    worker = NevaehAgentWorker.find(receipt.fetch('agent_worker_id'))
    assert_equal @website_worker.id, worker.nevaeh_os_agent_id
    binding.update!(status: 'paused')
    assert_raises(ArgumentError) { NevaehOs::AgentWorkforce.request!(worker: worker, actor: @actor, key: 'paused-builder-schedule') }
  end
  def test_native_capability_extension_keeps_application_context_and_adapter_contract
    NevaehCapability.create!(slug: 'susu.list', name: 'List Susus', domain: 'susu', intent_name: 'susu_list', handler: 'Susu::Workers::Pwa', queue: 'default', event_types: ['susu.list.requested'])
    values = {'name'=>'My savings groups', 'template_key'=>'capability:susu.list', 'worker_id'=>NevaehOsAgent.find_by!(user: @actor, system_key: 'finance').id,
      'fixed'=>{'context_site_id'=>@site.id.to_s}, 'patterns'=>'inspect my savings groups', 'sample_phrase'=>'inspect my savings groups', 'expected'=>{}}
    binding = draft(values); publish(binding)
    result = ask('inspect my savings groups')
    action = NevaehOsAction.find(result.fetch('action_id'))
    assert_equal @site.id, action.command.dig('command', 'site_id')
    assert_equal 'susu.list', action.command.dig('command', 'intent')
    NevaehCapability.find_by!(slug: 'susu.list').update!(enabled: false)
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(action) }
  end
  def test_same_phrase_with_different_assigned_workers_requires_clarification
    first = draft; publish(first)
    manager = NevaehOsAgent.find_by!(user: @actor, system_key: 'nevaeh')
    second = draft(attributes.merge('worker_id'=>manager.id)); publish(second)
    assert_equal 'needs_clarification', ask('prepare my service page called About us')['status']
    assert_empty NevaehOsAction.all
    @website_worker.update!(deleted_at: Time.current)
    # A stale assignment is a visible blocker, never an unscoped find or fallback.
    result = NevaehOs::Language.resolve('prepare my service page called About us', actor: @actor)
    assert_equal 'needs_clarification', result['status']
    refute result['command']
  end
  def test_marketing_request_uses_its_native_executor_instead_of_a_ten_task_guess
    result = ask('help me market my business', mode: 'reflect')
    assert_equal 'planned', result['status']
    assert_includes result['text'], 'marketing_kit'
    assert_empty NevaehTaskDialogue.all
    assert_empty NevaehOsAction.all
    target = NevaehOs::TaskBuilder.command('marketing_kit', {'site_id'=>@site.id})
    assert_equal 'growth.marketing_kit', NevaehOs::Agents.capability(target)
    assert_equal @site.id, target['site_id']
    ['create a feature page', 'build me a feature page with videos', 'make my features webpage with overview videos'].each do |phrase|
      assert_equal 'feature_showcase', NevaehOs::Command.parse(phrase)['kind']
      assert_nil NevaehOs::TaskDialogues.handle(actor: @actor, text: phrase, request_key: SecureRandom.uuid, mode: 'reflect')
    end
  end
end

class NevaehTaskBuilderUiChecks < NevaehTaskBuilderChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def test_actual_builder_template_renders_draft_and_tested_revision_with_escaped_values
    require 'action_view'
    binding = draft(attributes.merge('name'=>'Service <script>window.BAD=1</script>'))
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT, 'app/views')]), {}, nil)
    class << view
      def main_app = self
      def protect_against_forgery? = false
      def employee_nevaeh_factory_path(**query) = '/employee/nevaeh/factory?' + URI.encode_www_form(query)
      def employee_nevaeh_factory_task_extensions_path = '/employee/nevaeh/factory/tasks'
      def employee_nevaeh_factory_control_task_extension_path(task, operation:) = "/employee/nevaeh/factory/tasks/#{task.id}/#{operation}"
      def employee_nevaeh_factory_export_task_extension_path(task) = "/employee/nevaeh/factory/tasks/#{task.id}/export"
      def dashboard_nevaeh_guide_path(**query) = '/dashboard/nevaeh/guide?' + URI.encode_www_form(query)
      def dashboard_nevaeh_os_path = '/dashboard/nevaeh'
    end
    assignments = {task_extensions: [binding], task_extension: binding, task_templates: NevaehOs::TaskBuilder.templates(@actor),
      task_template: NevaehOs::TaskBuilder.template!(@actor, 'website_page'), task_workers: NevaehOs::TaskBuilder.eligible_workers(@actor, 'website_page'),
      documents: [@doc]}
    assignments.each { |key, value| view.instance_variable_set("@#{key}", value) }
    draft_html = view.render(partial: 'employee/nevaeh_factory/task_builder')
    refute_includes draft_html, 'Activate this tested revision'
    assert_includes draft_html, 'Test routing &amp; permissions'
    assert_includes draft_html, 'extension[expected][title]'
    assert_includes draft_html, 'Service &lt;script&gt;window.BAD=1&lt;/script&gt;'
    refute_includes draft_html, '<script>window.BAD=1</script>'
    publish(binding)
    html = view.render(partial: 'employee/nevaeh_factory/task_builder')
    assert_includes html, 'Activate this tested revision'
    assert_includes html, 'Pause task'
    assert_includes html, 'Download task package'
    FileUtils.mkdir_p(File.join(ROOT, 'tmp'))
    File.write(File.join(ROOT, 'tmp/nevaeh-task-builder-preview.html'), '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/lightek/nevaeh/control-center.css"><link rel="stylesheet" href="/lightek/nevaeh/factory.css"><body style="background:#15121b;margin:0;font-family:system-ui,sans-serif"><section class="nc">' + html + '</section>')
  end
end

# Exercise the actual controller endpoints with the host authentication adapter.
module Gatekeeper
  class LessonService
    class KnowledgeBaseUnavailable < StandardError; end
  end
end
module Employee
  class ApplicationController < ::ApplicationController
    def authorize!(operation, model)
      raise CanCan::AccessDenied unless Ability.new(current_user).can?(operation, model)
    end
  end
end
require File.join(ROOT, 'app/controllers/employee/nevaeh_factory_controller')
class NevaehTaskBuilderHttpChecks < ActionController::TestCase
  tests Employee::NevaehFactoryController
  def setup
    NevaehLanguageBinding.delete_all
    @actor = User.create!(role: 'super_admin')
    @other = User.create!(role: 'super_admin')
    @request.session[:actor_id] = @actor.id
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get '/employee/nevaeh/factory', to: 'employee/nevaeh_factory#index', as: :employee_nevaeh_factory
      post '/employee/nevaeh/factory/tasks', to: 'employee/nevaeh_factory#save_task_extension'
      get '/employee/nevaeh/factory/tasks/:id/export', to: 'employee/nevaeh_factory#export_task_extension'
      post '/employee/nevaeh/factory/tasks/:id/:operation', to: 'employee/nevaeh_factory#control_task_extension'
    end
    @controller.singleton_class.include(@routes.url_helpers)
  end
  def test_real_form_payload_test_activate_export_and_foreign_account_guard
    worker = NevaehOsAgent.create!(user: @actor, name: 'Server reviewer', role: 'IT', allowed_capabilities: ['operations.hosting.review'])
    doc = NevaehIntelligences::SoftwareLibrary.new.documents.find { |row| row[:path] == 'docs/nevaeh/tutorials/specialist_tasks.md' }
    post :save_task_extension, params: {document_id: doc[:id], extension: {name: 'Fleet review', template_key: 'hosting_review', worker_id: worker.id,
      patterns: "inspect our fleet\nreview our fleet", sample_phrase: 'inspect our fleet', fixed: {}, expected: {}}}
    assert_response :redirect
    binding = NevaehLanguageBinding.order(:id).last
    assert_equal @actor.id, binding.creator_id
    post :control_task_extension, params: {id: binding.id, operation: 'test'}
    assert_response :redirect
    assert binding.reload.builder_verification['passed']
    post :control_task_extension, params: {id: binding.id, operation: 'activate'}
    assert_equal 'active', binding.reload.status
    get :export_task_extension, params: {id: binding.id}
    assert_response :success
    assert_equal binding.patterns, JSON.parse(response.body)['patterns']
    assert_includes response.headers['Content-Disposition'], "nevaeh-task-#{binding.id}.json"
    @request.session[:actor_id] = @other.id
    assert_raises(ActiveRecord::RecordNotFound) { get :export_task_extension, params: {id: binding.id} }
    assert_raises(ActiveRecord::RecordNotFound) { post :control_task_extension, params: {id: binding.id, operation: 'pause'} }
    assert_equal 'active', binding.reload.status
  end
end
