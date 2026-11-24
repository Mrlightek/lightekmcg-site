# frozen_string_literal: true

class Dashboard::ReleaseAssuranceController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :authorize_operator
  before_action :set_candidate, only: %i[show publish accept prepare deploy retire recommend promote learn rollback
    assign verify_feedback evidence retest]
  rescue_from ReleaseAssurance::Policy::Denied, ReleaseAssurance::Source::Invalid, ActiveRecord::RecordInvalid,
    Gatekeeper::WebsiteDeployment::Invalid, Gatekeeper::Compute::StagingRequests::Invalid, ArgumentError, with: :invalid_action

  def index
    @candidates = candidates.order(id: :desc).limit(100)
    @testers = testers.order(:name).limit(100)
  end

  def show
    @readiness = ReleaseAssurance::Readiness.new(@candidate).evaluation
    @environments = @candidate.environments.includes(:provisioning_request).order(id: :desc)
    @runs = @candidate.runs.order(id: :desc).limit(100)
    @defects = @candidate.defects.includes(:run, :retest).order(id: :desc)
    @testers = testers.where(offboarded_at: nil).order(:name)
    @rollback_candidates = candidates.where(profile: @candidate.profile, state: "published")
      .where.not(id: @candidate.id).where.not(promotion_approved_at: nil).order(promotion_approved_at: :desc).limit(20)
  end

  def create
    ReleaseAssurance::Policy.runner!
    profile = params.require(:profile)
    requested_sources = params[:sources].to_s
    requested_sources = ([*ReleaseAssurance::Source::MSP, requested_sources]).join(" ") if profile == "msp"
    sources = ReleaseAssurance::Source.selectors(requested_sources)
    @candidate = candidates.create!(name: params.require(:name), profile: profile, selectors: sources, publication_key: SecureRandom.uuid)
    ReleaseAssurance::AssemblyJob.perform_later(@candidate.id)
    redirect_to_candidate("Nevaeh queued candidate assembly.")
  end

  def publish
    ReleaseAssurance::Policy.runner!
    raise ReleaseAssurance::Policy::Denied, "Confirm the exact reviewed candidate revision" unless
      @candidate.state == "assembled" && params[:reviewed_revision] == @candidate.source_sha
    ReleaseAssurance::AssemblyJob.perform_later(@candidate.id, true)
    redirect_to_candidate("Publication of the reviewed revision is queued.")
  end

  def accept
    ReleaseAssurance::Policy.runner!
    ReleaseAssurance::AcceptanceJob.perform_later(@candidate.id)
    if (environment = @candidate.environments.where(state: "ready").where("expires_at > ?", Time.current).last)
      ReleaseAssurance::BrowserJob.perform_later(environment.id)
    end
    redirect_to_candidate("Acceptance refresh queued.")
  end

  def prepare
    prepare_target!(@candidate)
    redirect_to_candidate("Staging request is ready for Gatekeeper review.")
  end

  def rollback
    previous = candidates.where(profile: @candidate.profile, state: "published")
      .where.not(promotion_approved_at: nil).where.not(id: @candidate.id).find(params.require(:rollback_candidate_id))
    prepare_target!(previous)
    redirect_to dashboard_release_assurance_path(previous),
      notice: "Rollback target prepared. Approve the fresh staging request through Gatekeeper.", status: :see_other
  end

  def deploy
    ReleaseAssurance::Staging.new(environment, current_user).approve!
    redirect_to_candidate("Approved staging deployment queued.")
  end

  def retire
    ReleaseAssurance::Staging.new(environment, current_user).queue_retirement!
    redirect_to_candidate("Staging cleanup queued.")
  end

  def recommend
    ReleaseAssurance::Nevaeh.review!(@candidate, current_user)
    redirect_to_candidate("Nevaeh reviewed the evidence and filed defects for failed checks.")
  end

  def promote
    ReleaseAssurance::Readiness.new(@candidate).approve!(current_user, evidence_digest: params[:evidence_digest])
    redirect_to_candidate("Production promotion approval recorded for this revision and evidence.")
  end

  def learn
    ReleaseAssurance::Nevaeh.learn!(@candidate, current_user)
    redirect_to_candidate("Nevaeh recorded the verified release in the knowledge base and improvement history.")
  end

  def register_tester
    raise ReleaseAssurance::Policy::Denied, "Record the tester's consent first" unless params[:consent] == "1"
    testers.create!(params.permit(:name, :email, :platform, :device_profile).merge(consented_at: Time.current))
    redirect_to dashboard_release_assurance_index_path, notice: "Tester registered.", status: :see_other
  end

  def offboard_tester
    tester = testers.find(params[:tester_id])
    tester.with_lock { tester.update!(offboarded_at: Time.current) }
    tester.assignments.where(revoked_at: nil).find_each { |assignment| revoke_assignment!(assignment) }
    redirect_to dashboard_release_assurance_index_path, notice: "Tester access revoked. Temporary account cleanup queued.", status: :see_other
  end

  def assign
    target = environment
    tester = testers.where(offboarded_at: nil).find(params.require(:tester_id))
    scenario = params.require(:scenario)
    platform, = ReleaseAssurance::Readiness::SCENARIOS.fetch(scenario) { raise ArgumentError, "Choose a test scenario" }
    raise ReleaseAssurance::Policy::Denied, "Use an active environment and a compatible tester device" unless
      target.active? && (platform.nil? || platform == tester.platform)
    @invite = SecureRandom.hex(32)
    tester.with_lock do
      raise ReleaseAssurance::Policy::Denied, "Tester was offboarded" if tester.offboarded_at
      target.assignments.create!(tester: tester, scenario: scenario, invite_digest: Digest::SHA256.hexdigest(@invite),
        expires_at: [48.hours.from_now, target.expires_at].min)
    end
    response.headers["Cache-Control"] = "private, no-store"
    render :invitation
  end

  def verify_feedback
    ReleaseAssurance::Feedback.verify!(@candidate.runs.find(params[:run_id]), current_user)
    redirect_to_candidate("Beta evidence reviewed.")
  end

  def evidence
    run = @candidate.runs.find(params[:run_id])
    return head :not_found unless run.screenshot.attached?

    response.headers["Cache-Control"] = "private, no-store"
    send_data run.screenshot.download, filename: "acceptance-#{run.id}.png", type: "image/png", disposition: "attachment"
  end

  def retest
    ReleaseAssurance::Nevaeh.retest!(@candidate.defects.find(params[:defect_id]), current_user,
      @candidate.runs.find(params.require(:run_id)))
    redirect_to_candidate("Passing retest attached to the defect.")
  end

  private

  def prepare_target!(candidate)
    hostname = params.require(:hostname).to_s.strip.downcase
    budget = Integer(params.require(:budget_cents))
    hours = Integer(params.require(:hours))
    ApplicationRecord.transaction do
      request = if params[:request_id].present?
        ProvisioningRequest.find(params[:request_id])
      else
        ReleaseAssurance::Staging.create_request!(actor: current_user, hostname: hostname, budget_cents: budget, hours: hours)
      end
      ReleaseAssurance::Staging.prepare!(candidate: candidate, actor: current_user, request: request,
        hostname: hostname, budget_cents: budget, hours: hours)
    end
  end

  def authorize_operator
    ReleaseAssurance::Policy.authorize!(current_user)
  rescue ReleaseAssurance::Policy::Denied
    head :forbidden
  end

  def candidates = ReleaseAssurance::Candidate.where(operator: current_user)
  def testers = ReleaseAssurance::Tester.where(operator: current_user)
  def set_candidate = @candidate = candidates.find(params[:id])
  def environment = @candidate.environments.find(params.require(:environment_id))

  def revoke_assignment!(assignment)
    assignment.with_lock { assignment.update!(revoked_at: Time.current) }
    ReleaseAssurance::RevokeAccountJob.perform_later(assignment.id)
  end

  def redirect_to_candidate(notice)
    redirect_to dashboard_release_assurance_path(@candidate), notice: notice, status: :see_other
  end

  def invalid_action(error)
    path = @candidate&.persisted? ? dashboard_release_assurance_path(@candidate) : dashboard_release_assurance_index_path
    redirect_to path, alert: error.message, status: :see_other
  end
end
