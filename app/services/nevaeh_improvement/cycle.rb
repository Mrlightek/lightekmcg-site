# frozen_string_literal: true

require 'digest'

module NevaehImprovement
  class Cycle
    BASELINE = 'baseline'
    MIN_EXAMPLES = 12
    MIN_PER_GROUP = 6
    WINDOW = 7.days

    def self.adapters = {'agency_onboarding' => Agency, 'purchased_service' => PurchasedService, 'release_assurance' => ReleaseAssurance}

    def initialize(operator, workflow)
      @operator = operator
      @workflow = workflow
      @adapter = self.class.adapters.fetch(workflow)
    end

    def observe!(subject_id, signals, comparison_key: subject_id.to_s)
      @operator.with_lock do
        return unless authorized?

        existing = observations.find_by(comparison_key: comparison_key)
        return existing if existing&.subject_id == subject_id
        return if existing

        playbook = current
        ApplicationRecord.transaction(requires_new: true) do
          observations.create!(subject_id: subject_id, playbook: playbook, started_at: Time.current,
            signals: signals, comparison_key: comparison_key,
            cohort: playbook&.status == 'trial' ? cohort(subject_id, playbook.id) : 'baseline')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # A repeated help request about the same purchase belongs to its first observation.
      observations.find_by(subject_id: subject_id, comparison_key: comparison_key)
    end

    def strategy(row)
      playbook = row.playbook
      return BASELINE unless playbook
      return playbook.parent&.strategy || BASELINE if playbook.status == 'rolled_back' || row.cohort == 'control'

      playbook.strategy
    end

    def evaluate!
      @operator.with_lock do
        return unless authorized?

        playbook = current
        playbook&.status == 'trial' ? assess!(playbook) : propose!(playbook)
      end
    end

    def decide!(id, approve:)
      @operator.with_lock do
        raise ActiveRecord::RecordNotFound unless authorized?

        parent = current
        raise ActiveRecord::RecordNotFound if parent&.status == 'trial'

        revision = playbooks.find_by!(id: id, status: 'proposed', parent: parent)
        if approve
          raise ActiveRecord::RecordNotFound unless @adapter.available_for?(@operator) &&
            safe_replay?(revision.strategy, revision.evidence.fetch('holdout_ids'))

          parent&.update!(status: 'superseded')
          revision.update!(status: 'trial', activated_at: Time.current)
        else
          revision.update!(status: 'declined')
        end
      end
    end

    private

    def authorized? = NevaehOnboarding::StandingAssignment.operator?(@operator)
    def playbooks = NevaehResolutionPlaybook.where(operator: @operator, workflow: @workflow)
    def observations = NevaehResolutionObservation.where(operator: @operator, workflow: @workflow)
    def current = playbooks.find_by(status: %w[trial active])
    def measured
      observations.where.not(measured_at: nil).where("COALESCE(CAST(outcome ->> 'excluded' AS TEXT), 'false') NOT IN ('true', '1')")
    end

    def cohort(subject_id, playbook_id)
      Digest::SHA256.hexdigest([@workflow, playbook_id, subject_id].join(':')).last.to_i(16).even? ? 'candidate' : 'control'
    end

    def propose!(parent)
      return if playbooks.exists?(status: 'proposed', parent: parent)

      # Keep failed rollout cases apart from the chronological training/holdout split.
      rows = measured.order(started_at: :desc, id: :desc).limit(120).to_a.reverse
      return if rows.size < MIN_EXAMPLES

      training, holdout = rows.each_slice((rows.size + 1) / 2).to_a
      baseline = parent&.strategy || BASELINE
      options = @adapter.strategies - [baseline]
      options -= playbooks.where(status: %w[rolled_back declined]).distinct.pluck(:strategy)
      option = options.max_by { |key| unmet(training, key) }
      return unless option && unmet(training, option).positive? && unmet(holdout, option).positive?
      return unless safe_replay?(option, holdout.map(&:id))

      fingerprint = Digest::SHA256.hexdigest([parent&.id, option, rows.map(&:id)].to_json)
      playbooks.find_or_create_by!(evidence_digest: fingerprint) do |revision|
        revision.assign_attributes(parent: parent, strategy: option, status: 'proposed',
          evidence: {training_ids: training.map(&:id), holdout_ids: holdout.map(&:id),
            held_out_unresolved: unmet(holdout, option), regression_ids: regression_ids})
      end
    end

    def unmet(rows, strategy)
      rows.count { |row| !row.outcome['verified'] && @adapter.action(strategy, row.signals) }
    end

    def regression_ids
      playbooks.where(status: 'rolled_back').order(id: :desc).limit(20)
        .flat_map { |revision| revision.evidence.fetch('regression_ids', []) }.uniq
    end

    def safe_replay?(strategy, ids)
      return false unless @adapter.strategies.include?(strategy)
      return false unless @adapter.negative_examples.all? { |signals| @adapter.action(strategy, signals).nil? }

      held_out = measured.where(id: ids).to_a
      return false unless held_out.size == ids.size

      held_out.all? { |row| @adapter.accepts?(@adapter.action(strategy, row.signals), row.signals) } &&
        measured.where(id: regression_ids).all? do |row|
          @adapter.action(strategy, row.signals).nil? || !@adapter.action_regression?(row, strategy)
        end
    end

    def assess!(playbook)
      rows = measured.where(playbook: playbook)
      candidate = rows.where(cohort: 'candidate').order(:id).limit(120).to_a
      control = rows.where(cohort: 'control').order(:id).limit(120).to_a
      regressions = candidate.select { |row| row.outcome['regression'] }
      return if regressions.empty? && [candidate.size, control.size].min < MIN_PER_GROUP

      scores = {'candidate' => metrics(candidate), 'control' => metrics(control)}
      advanced = regressions.empty? &&
        quality(scores.fetch('candidate')) > quality(scores.fetch('control'))
      if advanced
        playbook.update!(status: 'active', evidence: playbook.evidence.merge('rollout' => scores))
      else
        lost = candidate.reject { |row| row.outcome['verified'] }
        playbook.update!(status: 'rolled_back', evidence: playbook.evidence.merge('rollout' => scores,
          'regression_ids' => (regressions + lost).map(&:id).uniq))
        playbook.parent&.update!(status: 'active')
      end
    end

    def metrics(rows)
      {'count' => rows.size, 'verified' => rows.count { |row| row.outcome['verified'] },
        'handoffs' => rows.count { |row| row.outcome['handoff'] },
        'reopened' => rows.count { |row| row.outcome['reopened'] },
        'regressions' => rows.count { |row| row.outcome['regression'] }}
    end

    def quality(metrics)
      (metrics['verified'] - metrics['handoffs'] - metrics['reopened']).fdiv(metrics['count'])
    end
  end
end
