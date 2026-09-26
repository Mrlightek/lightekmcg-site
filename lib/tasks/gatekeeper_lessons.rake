namespace :gatekeeper do
  desc "Record the DymondDash controller-shell contract lesson in the Knowledge Base"
  task learn_dymond_dash_controller_contract: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-DYMOND-DASH-CONTROLLER-CONTRACT",
      title: "DymondDash shell requires the DymondDash controller contract",
      capability: "render_dymond_dash_shell",
      symptom: "A host-app page renders with the DymondDash layout but returns HTTP 500. Passenger reports NameError: undefined local variable or method `account_plan` from dymond_dash/shared/_sidebar.html.erb.",
      cause: "The feature controller inherited directly from ApplicationController while rendering dymond_dash/layouts/dymond_dash. The shell expects account_plan, current_plan_slug, nav_items, and related behavior supplied by DymondDash::ApplicationController.",
      remediation: "Make the host feature controller inherit from DymondDash::ApplicationController and preserve its existing routes, actions, callbacks, and business logic. Do not duplicate the DymondDash helper contract into each feature controller.",
      verification: "Run bin/rails zeitwerk:check. Verify SusuGroupsController, SusuMembershipsController, and SusuMatchPreferencesController inherit from DymondDash::ApplicationController. Confirm the controller contract exposes account_plan/current_plan_slug/nav_items. Then request /susu_groups and verify HTTP 200 with the DymondDash sidebar present.",
      metadata: {
        "affected_controllers" => %w[
          SusuGroupsController
          SusuMembershipsController
          SusuMatchPreferencesController
        ],
        "observed_environment" => "production",
        "web_server" => "Apache + Phusion Passenger"
      }
    )

    identifier =
      if article.respond_to?(:article_id) && article.article_id.present?
        article.article_id
      elsif article.respond_to?(:slug) && article.slug.present?
        article.slug
      else
        article.id
      end

    puts "Gatekeeper lesson recorded: #{identifier}"
  rescue Gatekeeper::LessonService::KnowledgeBaseUnavailable => e
    warn "Gatekeeper lesson not persisted yet: #{e.message}"
    warn "The remediation is installed; rerun this task when DymondKb is available."
  end
end
