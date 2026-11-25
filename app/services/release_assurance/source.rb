# frozen_string_literal: true

require "open3"
require "tmpdir"

module ReleaseAssurance
  class Source
    class Invalid < StandardError; end

    ORIGIN = "https://github.com/Mrlightek/lightekmcg-site.git"
    SHA = /\A[0-9a-f]{40}\z/
    BRANCH = /\A[a-zA-Z0-9][a-zA-Z0-9._\/-]{0,199}\z/
    PUBLICATION_REF = /\Arelease-candidates\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    MSP = %w[pr:426 pr:432 pr:433].freeze
    MSP_WORKFLOWS = %w[it-device-agent it-services-business-acceptance batch-d-acceptance].freeze
    IDENTITY = {
      "GIT_AUTHOR_NAME" => "Lightek Release Assurance",
      "GIT_AUTHOR_EMAIL" => "release-assurance@lightekmcg.com",
      "GIT_COMMITTER_NAME" => "Lightek Release Assurance",
      "GIT_COMMITTER_EMAIL" => "release-assurance@lightekmcg.com",
      "GIT_TERMINAL_PROMPT" => "0"
    }.freeze

    def self.selectors(input)
      selectors = input.to_s.split(/[\s,]+/).reject(&:empty?)
      raise Invalid, "Choose one to ten distinct source references" unless (1..10).cover?(selectors.size) && selectors.uniq == selectors
      selectors.each { |selector| ref_for(selector) }
      selectors
    end

    def self.ref_for(selector)
      kind, value = selector.split(":", 2)
      case kind
      when "pr"
        return "refs/pull/#{value}/head" if value&.match?(/\A[1-9][0-9]{0,8}\z/)
      when "branch"
        if value&.match?(BRANCH) && !value.start_with?("release-candidates/") &&
            value.split("/").none? { |part| part.empty? || part.start_with?(".") || part.end_with?(".lock") } &&
            !value.include?("..") && !value.end_with?(".")
          return "refs/heads/#{value}"
        end
      when "commit"
        return value if value&.match?(SHA)
      end
      raise Invalid, "Use pr:NUMBER, branch:NAME or commit:SHA"
    end

    def initialize(origin: ORIGIN)
      @origin = origin
    end

    def assemble(selectors, pinned_base: nil, pinned_sources: nil)
      Dir.mktmpdir("release-assurance-") do |dir|
        git!(dir, "init", "-q")
        base = fetch(dir, pinned_base || "refs/heads/develop")
        sources = selectors.each_with_index.map do |selector, index|
          ref = pinned_sources ? pinned_sources.fetch(index).fetch("sha") : self.class.ref_for(selector)
          { "selector" => selector, "sha" => fetch(dir, ref) }
        end
        # Report selected PRs that already contain another selected head.
        sources.each do |source|
          source["includes"] = sources.filter_map do |other|
            other["selector"] if other["sha"] != source["sha"] && ancestor?(dir, other["sha"], source["sha"])
          end
        end

        head = base
        sources.each do |source|
          sha = source.fetch("sha")
          next if ancestor?(dir, sha, head)

          output, status = git(dir, "merge-tree", "--write-tree", "--name-only", head, sha)
          if status.exitstatus == 1
            return { base_sha: base, sources: sources, conflicts: [source.fetch("selector")] }
          end
          tree = output.lines.first.to_s.strip
          raise Invalid, "Git could not calculate the candidate tree" unless status.success? && tree.match?(SHA)
          date = git!(dir, "show", "-s", "--format=%cI", sha)
          head = git!(dir, "commit-tree", tree, "-p", head, "-p", sha,
            "-m", "Stage #{source.fetch('selector')} at #{sha}", env: { "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date })
        end
        head = enable_msp_checks(dir, head) if (MSP - selectors).empty?
        yield dir, head if block_given?
        { base_sha: base, sources: sources, source_sha: head, conflicts: [] }
      end
    end

    def publish!(dir, sha, ref)
      raise Invalid, "Invalid candidate publication ref" unless ref.match?(/\Arelease-candidates\/[0-9a-f-]{36}\z/)
      git!(dir, "push", @origin, "#{sha}:refs/heads/#{ref}")
      raise Invalid, "Remote candidate differs from assembled revision" unless fetch(dir, "refs/heads/#{ref}") == sha
    end

    def verify_publication!(sha, ref)
      raise Invalid, "Enter the full reviewed candidate SHA" unless sha.match?(SHA)
      raise Invalid, "Enter a release-candidates/ branch" unless ref.match?(PUBLICATION_REF)

      qualified_ref = "refs/heads/#{ref}"
      output = git!(Dir.tmpdir, "-c", "http.lowSpeedLimit=1024", "-c", "http.lowSpeedTime=15",
        "ls-remote", "--exit-code", "--refs", "--", @origin, qualified_ref)
      raise Invalid, "Published candidate differs from the reviewed revision" unless output == "#{sha}\t#{qualified_ref}"

      true
    end

    def checkout(sha, ref)
      raise Invalid, "Invalid candidate revision" unless sha.match?(SHA)
      raise Invalid, "Invalid candidate publication ref" unless ref.match?(/\Arelease-candidates\/[0-9a-f-]{36}\z/)
      Dir.mktmpdir("staging-source-") do |dir|
        git!(dir, "init", "-q")
        raise Invalid, "Published candidate revision changed" unless fetch(dir, "refs/heads/#{ref}") == sha
        git!(dir, "checkout", "--detach", sha)
        yield dir
      end
    end

    private

    def enable_msp_checks(dir, head)
      git!(dir, "read-tree", head)
      MSP_WORKFLOWS.each do |name|
        path = ".github/workflows/#{name}.yml"
        workflow = git!(dir, "show", "#{head}:#{path}")
        next if workflow.match?(/^  push:/)

        raise Invalid, "Could not enable #{name} on the candidate ref" unless workflow.match?(/^on:$/)
        updated = workflow.sub(/^on:\n/, "on:\n  push:\n    branches: [\"release-candidates/**\"]\n") + "\n"
        blob, status = Open3.capture2(IDENTITY, "git", "-C", dir, "hash-object", "-w", "--stdin", stdin_data: updated)
        raise Invalid, "Could not store #{name} workflow" unless status.success?
        git!(dir, "update-index", "--cacheinfo", "100644,#{blob.strip},#{path}")
      end
      tree = git!(dir, "write-tree")
      return head if tree == git!(dir, "rev-parse", "#{head}^{tree}")

      date = git!(dir, "show", "-s", "--format=%cI", head)
      git!(dir, "commit-tree", tree, "-p", head, "-m", "Enable existing MSP CI on the reviewed candidate ref",
        env: { "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date })
    end

    def fetch(dir, ref)
      git!(dir, "-c", "http.lowSpeedLimit=1024", "-c", "http.lowSpeedTime=30",
        "fetch", "--no-tags", "--", @origin, ref)
      git!(dir, "rev-parse", "--verify", "FETCH_HEAD^{commit}")
    end

    def ancestor?(dir, ancestor, descendant)
      _, status = git(dir, "merge-base", "--is-ancestor", ancestor, descendant)
      raise Invalid, "Git could not check source ancestry" unless [0, 1].include?(status.exitstatus)
      status.success?
    end

    def git!(dir, *arguments, env: {})
      output, status = git(dir, *arguments, env: env)
      raise Invalid, "Git #{arguments.first} failed" unless status.success?
      output.strip
    end

    def git(dir, *arguments, env: {})
      output, _, status = Open3.capture3(IDENTITY.merge(env), "git", "-C", dir, *arguments)
      [output, status]
    end
  end
end
