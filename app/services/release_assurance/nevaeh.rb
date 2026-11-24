# frozen_string_literal: true

module ReleaseAssurance
  module Nevaeh
    def self.review!(candidate, actor)
      Policy.authorize!(actor, candidate)
      candidate.with_lock do
        candidate.runs.where(result: "failed").order(:id).find_each do |run|
          defect = candidate.defects.find_or_create_by!(run: run)
          next if defect.ticket_id

          ticket = Marlon::Ticket.find_or_initialize_by(related_type: "ReleaseAssurance::Defect", related_id: defect.id)
          if ticket.new_record?
            ticket.update!(number: "LT-RELEASE-#{defect.id}", category: "technical", status: "open",
              title: "Release assurance: #{run.check_key.humanize} failed",
              description: "Candidate #{candidate.id}, revision #{run.source_sha}, acceptance run #{run.id}. Review the evidence and retest the failed check.",
              priority: "high", urgency: 8, assigned_team: "Technical", assigned_rep: "Nevaeh",
              organization_name: "Lightek MCG", extra_fields: { "source" => "release_assurance", "run_id" => run.id })
          end
          defect.update!(ticket_id: ticket.id)
        end
      end
    end

    def self.learn!(candidate, actor)
      Policy.authorize!(actor, candidate)
      evaluation = Readiness.new(candidate).evaluation
      raise Policy::Denied, "Verified acceptance is required before recording a release lesson" if evaluation[:blockers].any?

      Gatekeeper::LessonService.record!(key: "release-assurance-#{candidate.id}-#{evaluation.fetch(:digest)}",
        title: "Verified release acceptance for #{candidate.source_sha.first(12)}", capability: "release_assurance",
        symptom: "A release candidate required staging and acceptance verification",
        cause: "Release #{candidate.source_sha} was reviewed on the #{candidate.profile} acceptance profile",
        remediation: "Reapply the acceptance profile to new candidates and retest any failed check",
        verification: "Accepted run IDs #{evaluation.fetch(:evidence_ids).join(', ')}",
        metadata: { "release_candidate_id" => candidate.id, "source_sha" => candidate.source_sha })
      if (observation = NevaehImprovement::Cycle.new(actor, "release_assurance").observe!(candidate.id,
          { "profile" => candidate.profile }, comparison_key: evaluation.fetch(:digest)))
        observation.update!(measured_at: Time.current, outcome: { "verified" => true, "evidence_ids" => evaluation.fetch(:evidence_ids) })
      end
    end

    def self.retest!(defect, actor, run)
      candidate = defect.candidate
      Policy.authorize!(actor, candidate)
      candidate.with_lock do
        original = defect.run
        unless defect.status == "open" && run.candidate_id == candidate.id && run.source_sha == candidate.source_sha &&
          run.check_key == original.check_key && run.kind == original.kind && run.result == "passed" && run.id > original.id
          raise Policy::Denied, "Select a later passing run of the same check on this candidate"
        end
        defect.update!(status: "verified", retest: run)
      end
    end
  end
end
