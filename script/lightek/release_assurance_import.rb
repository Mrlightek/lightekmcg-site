# frozen_string_literal: true

actor_id, publication_key, revision, *selectors = ARGV.reject { |arg| arg == "--" }
abort "Usage: bin/rails runner script/lightek/release_assurance_import.rb -- ACTOR_ID UUID SHA pr:426 pr:432 pr:433 pr:435" unless
  actor_id&.match?(/\A[1-9][0-9]*\z/) &&
  publication_key&.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/) &&
  revision&.match?(ReleaseAssurance::Source::SHA)

ReleaseAssurance::Policy.runner!
actor = User.find(actor_id)
ReleaseAssurance::Policy.authorize!(actor)
selectors = ReleaseAssurance::Source.selectors(selectors.join(" "))
abort "Choose the three reviewed MSP batch sources and the Batch E source" unless
  (ReleaseAssurance::Source::MSP - selectors).empty? && selectors.include?("pr:435")

source = ReleaseAssurance::Source.new
reviewed_tree = nil
plan = source.assemble(selectors) do |directory, sha|
  reviewed_tree = IO.popen([ "git", "-C", directory, "rev-parse", "#{sha}^{tree}" ], &:read).strip
end
abort "The selected PR heads conflict" unless reviewed_tree&.match?(ReleaseAssurance::Source::SHA) && plan.fetch(:conflicts).empty?

source.checkout(revision, "release-candidates/#{publication_key}") do |directory|
  tree = IO.popen([ "git", "-C", directory, "rev-parse", "HEAD^{tree}" ], &:read).strip
  abort "The published release tree differs from the current reviewed source heads" unless tree == reviewed_tree

  heads = [plan.fetch(:base_sha), *plan.fetch(:sources).map { |entry| entry.fetch("sha") }]
  abort "The published release is missing a reviewed source" unless heads.all? do |head|
    system("git", "-C", directory, "merge-base", "--is-ancestor", head, revision)
  end
end

candidate = ReleaseAssurance::Candidate.find_or_initialize_by(publication_key: publication_key)
if candidate.new_record?
  candidate.update!(name: "Lightek MSP", operator: actor, profile: "msp", state: "published",
    selectors: selectors, base_sha: plan.fetch(:base_sha), sources: plan.fetch(:sources), source_sha: revision)
else
  ReleaseAssurance::Policy.authorize!(actor, candidate)
  abort "Existing candidate binding differs from the published release" unless
    candidate.source_sha == revision && candidate.profile == "msp" && candidate.state == "published"
end
puts JSON.generate(candidate_id: candidate.id, publication_ref: candidate.publication_ref, source_sha: candidate.source_sha)
