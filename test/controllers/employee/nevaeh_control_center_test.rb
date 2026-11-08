# frozen_string_literal: true
require "test_helper"
class NevaehControlCenterHttpTest < ActionDispatch::IntegrationTest
  PASSWORD = "nevaeh-control-center-http"
  def sign_in(role)
    @user = User.create!(email_address: "nevaeh-center-#{SecureRandom.hex(6)}@example.test", first_name: "Nevaeh", last_name: "Operator", role: role, password: PASSWORD)
    post session_path, params: {email_address: @user.email_address, password: PASSWORD}
    assert_response :redirect
  end
  def sections
    [{id: "draft", action: "content.generate", inputs: {format: "caption", context: {topic: "Opening night"}}, depends_on: []}]
  end
  test "anonymous and read-only employees cannot create workers" do
    get employee_nevaeh_control_center_path
    refute response.successful?
    sign_in("employee")
    get employee_nevaeh_control_center_path
    assert_response :success
    assert_select "section[aria-label='Nevaeh Control Center']"
    assert_select "form[data-worker-form]", count: 0
    assert_no_difference "NevaehWorkflow.count" do
      post employee_nevaeh_workers_path, params: {workflow: {name: "Denied", status: "active"}, sections_json: sections.to_json}
    end
  end
  test "administrator builds edits and queues an idempotent worker" do
    sign_in("super_admin")
    post employee_nevaeh_workers_path, params: {workflow: {name: "Caption worker", status: "active", interval_minutes: 60}, sections_json: sections.to_json}
    assert_response :redirect
    worker = NevaehWorkflow.order(:id).last
    assert worker.next_run_at
    get employee_nevaeh_control_center_path(tab: "workers", workflow_id: worker.id)
    assert_response :success
    assert_select "form[data-worker-form]"
    assert_difference "NevaehWorkflowRun.count", 1 do
      2.times { post run_employee_nevaeh_worker_path(worker), params: {request_key: "http-request-123"} }
    end
    run = worker.runs.last
    NevaehIntelligences::WorkflowRunJob.perform_now(run.id)
    assert run.reload.ticket
    assert_equal "ticket.structured.execute", run.ticket.extra_fields.dig("nevaeh_work_order", "intent_key")
    patch employee_nevaeh_worker_path(worker), params: {workflow: {name: "Paused", status: "paused", lock_version: worker.lock_version}, sections_json: sections.to_json}
    assert_response :redirect
    assert_nil worker.reload.next_run_at
    patch employee_nevaeh_worker_path(worker), params: {workflow: {name: "Stale", lock_version: 0}, sections_json: sections.to_json}
    assert_response :unprocessable_entity
    assert_equal "Paused", worker.reload.name
  end
  test "native model can be built and used through a writing service" do
    sign_in("super_admin")
    post employee_nevaeh_inference_models_path, params: {inference_model: {name: "Native storyteller", enabled: "1"}, rules_json: [{id: "premiere", format: "caption", keywords: ["film"], templates: ["{topic}: {goal}."], weight: 1}].to_json, examples_json: "[]", lexicon_json: {film: ["movie"]}.to_json}
    assert_response :redirect
    model = NevaehInferenceModel.order(:id).last
    post employee_nevaeh_writing_profiles_path, params: {profile: {name: "Studio captions", format: "caption", provider: "inference", inference_model_id: model.id, enabled: "1"}, templates: ""}
    assert_response :redirect
    profile = NevaehWritingProfile.order(:id).last
    post employee_nevaeh_write_path, params: {format: "caption", profile_id: profile.id, context: {topic: "movie premiere", goal: "open tonight"}}, as: :json
    assert_response :success
    result = response.parsed_body
    assert_equal "movie premiere: open tonight.", result["text"]
    assert_equal "premiere", result.dig("inference", "matched_rule")
    assert result["draft"]
    get employee_nevaeh_control_center_path(tab: "models", model_id: model.id)
    assert_response :success
    assert_select "form[data-inference-form]"
  end
  test "sidebar persists to the current account and rejects remote destinations" do
    sign_in("super_admin")
    entries = [{id: "custom-studio", label: "My Studio", group: "Creative", path: "/lightek/index.html#/studio"}]
    patch dashboard_nevaeh_navigation_path, params: {navigation_json: entries.to_json}
    assert_response :redirect
    assert_equal entries.first[:path], NevaehWorkspacePreference.find_by!(user: @user).navigation.first["path"]
    get employee_nevaeh_control_center_path(tab: "navigation")
    assert_response :success
    assert_select "a[href='/lightek/index.html#/studio']", text: /My Studio/
    entries.first[:path] = "//untrusted.test"
    patch dashboard_nevaeh_navigation_path, params: {navigation_json: entries.to_json}
    assert_response :redirect
    assert_equal "/lightek/index.html#/studio", NevaehWorkspacePreference.find_by!(user: @user).navigation.first["path"]
  end
end
