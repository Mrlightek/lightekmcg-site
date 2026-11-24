# frozen_string_literal: true

module ReleaseAssurance
  module Feedback
    STATUSES = %w[passed failed blocked].freeze

    def self.record!(assignment, result:, note:, screenshot: nil)
      raise Policy::Denied, "Choose a result and enter a redacted summary of 10 to 1000 characters" unless STATUSES.include?(result) &&
        (10..1000).cover?(note.length)
      # Store textual evidence with common credentials, emails and links removed.
      note = note.gsub(%r{https?://\S+|\S+@\S+|\b(?:password|token|secret|authorization)\s*[:=]\s*\S+|\b[a-zA-Z0-9_-]{32,}\b}i, "[redacted]")
      candidate = assignment.environment.candidate
      candidate.with_lock do
        raise Policy::Denied, "Assignment is closed" unless assignment.reload.active?
        raise Policy::Denied, "Feedback was already submitted" if candidate.runs.exists?(assignment: assignment)

        run = candidate.runs.create!(environment: assignment.environment, assignment: assignment, source_sha: candidate.source_sha,
          check_key: assignment.scenario, kind: "real_world", result: "blocked",
          evidence: { "reported_result" => result, "summary" => note, "platform" => assignment.tester.platform })
        if screenshot
          raise Policy::Denied, "Use a redacted PNG under 2 MB" unless screenshot.is_a?(ActionDispatch::Http::UploadedFile) && screenshot.size <= 2.megabytes &&
            screenshot.content_type == "image/png"

          bytes = screenshot.read(2.megabytes + 1)
          attach_png!(run, bytes)
        end
        run
      end
    end

    def self.verify!(run, actor)
      candidate = run.candidate
      Policy.authorize!(actor, candidate)
      candidate.with_lock do
        assignment = run.assignment
        raise Policy::Denied, "Feedback is no longer pending" unless run.reload.result == "blocked" && run.evidence["reviewer_id"].nil? &&
          assignment && assignment.environment.active? && assignment.environment.candidate_id == candidate.id
        run.update!(result: run.evidence.fetch("reported_result"),
          evidence: run.evidence.merge("reviewer_id" => actor.id, "reviewed_at" => Time.current.iso8601))
      end
    end

    def self.attach_png!(run, bytes)
      header = "\x89PNG\r\n\x1a\n".b
      raise Policy::Denied, "Expected a small PNG screenshot" unless bytes.start_with?(header) && bytes.bytesize <= 2.megabytes

      clean = header.dup
      offset = header.bytesize
      types = []
      while offset + 12 <= bytes.bytesize
        size, type = bytes.byteslice(offset, 8).unpack("Na4")
        raise Policy::Denied, "Invalid PNG screenshot" if offset + size + 12 > bytes.bytesize
        if %w[IHDR PLTE tRNS IDAT IEND].include?(type)
          types << type
          clean << bytes.byteslice(offset, size + 12)
        end
        offset += size + 12
        break if type == "IEND"
      end
      width, height = clean.byteslice(16, 8).to_s.unpack("NN")
      unless types.first == "IHDR" && types.last == "IEND" && types.include?("IDAT") &&
          (1..4096).cover?(width) && (1..4096).cover?(height)
        raise Policy::Denied, "Invalid PNG screenshot"
      end
      run.screenshot.attach(io: StringIO.new(clean), filename: "acceptance.png", content_type: "image/png", identify: false)
    end
  end
end
