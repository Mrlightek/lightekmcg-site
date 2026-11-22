# frozen_string_literal: true

require 'digest'

module NevaehOnboarding
  class Improvement
    BASELINE_HOURS = 24
    OPTIONS = [12, 24, 48].freeze
    OBSERVATION_HOURS = 72
    MIN_REPLAY = 12
    MIN_ROLLOUT_PER_COHORT = 6

    def self.escalation_hours(entry)
      playbook = entry.playbook
      return BASELINE_HOURS unless playbook

      if entry.evaluation_cohort == 'candidate' && playbook.status.in?(%w[active superseded])
        playbook.escalate_after_hours
      else
        playbook.parent&.escalate_after_hours || BASELINE_HOURS
      end
    end

    def initialize(operator)
      @operator = operator
    end

    def evaluate!
      @operator.with_lock do
        return unless StandingAssignment.operator?(@operator)
        active = playbooks.find_by(status: 'active')
        if active
          compare_rollout!(active)
          return unless active.status == 'active' && active.evaluation.key?('rollout')
        end
        propose!(active)
      end
    end

    def promote!(id)
      @operator.with_lock do
        raise ActiveRecord::RecordNotFound unless StandingAssignment.operator?(@operator)
        active = playbooks.find_by(status: 'active')
        candidate = playbooks.where(status: 'proposed', parent: active).find(id)
        active&.update!(status: 'superseded', retired_at: Time.current)
        candidate.update!(status: 'active', activated_at: Time.current)
        playbooks.where(status: 'proposed').update_all(status: 'rejected', retired_at: Time.current)
      end
    end

    def reject!(id)
      @operator.with_lock do
        raise ActiveRecord::RecordNotFound unless StandingAssignment.operator?(@operator)
        playbooks.where(status: 'proposed').find(id).update!(status: 'rejected', retired_at: Time.current)
      end
    end

    # A higher score means more premature reviews or a longer delay for agencies
    # that still have no dashboard receipt at the end of the observation window.
    def self.loss(entry, hours)
      dashboard_hours = (entry.dashboard_at - entry.paid_at) / 3600.0 if entry.dashboard_at
      return dashboard_hours > hours ? 24 : 0 if dashboard_hours && dashboard_hours <= OBSERVATION_HOURS

      hours
    end

    def self.observed_loss(entry)
      observed_hours = (entry.dashboard_escalated_at - entry.paid_at) / 3600.0 if entry.dashboard_escalated_at
      loss(entry, [observed_hours || OBSERVATION_HOURS, OBSERVATION_HOURS].min)
    end

    private

    def playbooks = NevaehOnboardingPlaybook.where(operator: @operator)

    def mature_cases
      NevaehOnboardingCase.where(operator: @operator).where('paid_at <= ?', OBSERVATION_HOURS.hours.ago)
        .where.not(id: NevaehOnboardingCase.where(blocker: 'eligibility_changed').select(:id))
    end

    def score(rows, hours)
      rows.sum { |entry| self.class.loss(entry, hours) }
    end

    def propose!(active)
      source = mature_cases.order(paid_at: :desc, id: :desc).limit(120).to_a.reverse
      return if source.size < MIN_REPLAY || playbooks.exists?(status: 'proposed', parent: active)

      # Chronological holdout. Rollout regressions remain replay cases across rounds.
      split = source.size / 2
      training, holdout = source.take(split), source.drop(split)
      guards = playbooks.where(status: 'rolled_back').order(id: :desc).limit(10)
        .flat_map { |revision| revision.evaluation.fetch('regression_case_ids', []) }.uniq
      regressions = mature_cases.where(id: guards).to_a
      baseline = active&.escalate_after_hours || BASELINE_HOURS
      candidate = OPTIONS.min_by { |hours| [score(training, hours), (baseline - hours).abs] }
      return if candidate == baseline || score(holdout, candidate) >= score(holdout, baseline)
      return if regressions.any? { |row| self.class.loss(row, candidate) > self.class.loss(row, baseline) }

      evidence = source.map { |row| [row.id, row.paid_at.iso8601, row.dashboard_at&.iso8601] }
      digest = Digest::SHA256.hexdigest([active&.id, candidate, evidence, guards.sort].to_json)
      playbooks.find_or_create_by!(evidence_digest: digest) do |revision|
        revision.assign_attributes(parent: active, status: 'proposed', escalate_after_hours: candidate,
          evaluation: {baseline_hours: baseline, train_ids: training.map(&:id), holdout_ids: holdout.map(&:id),
            baseline_loss: score(holdout, baseline), candidate_loss: score(holdout, candidate), regression_case_ids: regressions.map(&:id)})
      end
    end

    def compare_rollout!(active)
      cohort = mature_cases.where(playbook: active).order(id: :desc)
      candidate = cohort.where(evaluation_cohort: 'candidate').limit(100).to_a
      control = cohort.where(evaluation_cohort: 'control').limit(100).to_a
      return if [candidate.size, control.size].min < MIN_ROLLOUT_PER_COHORT

      baseline = active.parent&.escalate_after_hours || BASELINE_HOURS
      proposed = active.escalate_after_hours
      candidate_loss = candidate.sum { |row| self.class.observed_loss(row) }.fdiv(candidate.size)
      control_loss = control.sum { |row| self.class.observed_loss(row) }.fdiv(control.size)
      regression = candidate.select { |row| self.class.loss(row, proposed) > self.class.loss(row, baseline) }
      rollout = {candidate_cases: candidate.size, control_cases: control.size,
        candidate_average_loss: candidate_loss.round(2), control_average_loss: control_loss.round(2)}
      if candidate_loss > control_loss && score(candidate, proposed) > score(candidate, baseline)
        active.update!(status: 'rolled_back', retired_at: Time.current,
          evaluation: active.evaluation.merge('rollout' => rollout, 'regression_case_ids' => regression.map(&:id)))
        active.parent&.update!(status: 'active', retired_at: nil)
        playbooks.where(status: 'proposed', parent: active).update_all(status: 'rejected', retired_at: Time.current)
      else
        evaluation = active.evaluation.merge('rollout' => rollout)
        active.update!(evaluation: evaluation) if evaluation != active.evaluation
      end
    end
  end
end
