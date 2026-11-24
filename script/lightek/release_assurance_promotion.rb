# frozen_string_literal: true

actor_id, candidate_id, sha = ARGV.reject { |argument| argument == "--" }
abort "Usage: bin/rails runner script/lightek/release_assurance_promotion.rb -- ACTOR_ID CANDIDATE_ID SHA" unless
  actor_id&.match?(/\A[1-9][0-9]*\z/) && candidate_id&.match?(/\A[1-9][0-9]*\z/) &&
    sha&.match?(ReleaseAssurance::Source::SHA)

ReleaseAssurance::Policy.runner!
actor = User.find(actor_id)
candidate = ReleaseAssurance::Candidate.find(candidate_id)
decision = ReleaseAssurance::Readiness.new(candidate).authorize_promotion!(actor, source_sha: sha)
puts JSON.generate(candidate_id: candidate.id, source_sha: sha, approved_by: candidate.promotion_approver_id,
  evidence_digest: decision.fetch(:digest))
