# frozen_string_literal: true
require "open3"
require "digest"
require "tmpdir"
require "fileutils"
require "base64"
require "rbconfig"

module NevaehIntelligences
  # The existing reviewed template becomes a tested commit on an engineering
  # branch. No source from ticket prose is evaluated or promoted to production.
  module StructuredRepository
    PATH = "app/services/nevaeh_generated/metadata_normalizer.rb"
    module_function

    def root!
      root = File.expand_path(ENV["NEVAEH_ENGINEERING_WORKSPACE"].presence || Rails.root.join("tmp", "nevaeh-engineering", "workspace").to_s)
      raise StructuredTicket::Invalid, "Engineering workspace must be separate from the live application" if root == File.realpath(Rails.root)
      FileUtils.mkdir_p(File.dirname(root))
      File.open("#{root}.bootstrap.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        unless File.directory?(File.join(root, ".git"))
          raise StructuredTicket::Invalid, "Engineering workspace contains unrelated files" if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
          expected = ENV.fetch("NEVAEH_ENGINEERING_BRANCH", "feat/nevaeh-historical-backlog-20261031")
          raise StructuredTicket::Invalid, "Engineering branch required" if expected.blank? || %w[main master HEAD].include?(expected)
          _out, _error, status = Open3.capture3({"GIT_TERMINAL_PROMPT" => "0"}, "git", "clone", "--single-branch", "--branch", expected,
            "https://github.com/Mrlightek/lightekmcg-site.git", root)
          raise StructuredTicket::Invalid, "Engineering workspace clone failed" unless status.success?
        end
      end
      root = File.realpath(root)
      raise StructuredTicket::Invalid, "Engineering workspace must be separate from the live application" if root == File.realpath(Rails.root)
      branch = run!(root, "rev-parse", "--abbrev-ref", "HEAD").strip
      expected = ENV.fetch("NEVAEH_ENGINEERING_BRANCH", "feat/nevaeh-historical-backlog-20261031")
      raise StructuredTicket::Invalid, "Engineering branch mismatch" unless branch == expected && !%w[main master HEAD].include?(branch)
      remote = run!(root, "remote", "get-url", "origin").strip
      raise StructuredTicket::Invalid, "Unexpected engineering repository" unless ["https://github.com/Mrlightek/lightekmcg-site.git", "git@github.com:Mrlightek/lightekmcg-site.git"].include?(remote)
      root
    end

    def run!(root, *args, push: false)
      env = {"GIT_TERMINAL_PROMPT" => "0", "GIT_HTTP_LOW_SPEED_LIMIT" => "1", "GIT_HTTP_LOW_SPEED_TIME" => "30"}
      if push
        token = ENV["NEVAEH_ENGINEERING_GITHUB_TOKEN"].presence || ENV["GITHUB_ACTIONS_TOKEN"].presence
        raise StructuredTicket::Invalid, "Configure the existing GitHub integration token for branch writes" unless token
        env.merge!("GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
          "GIT_CONFIG_VALUE_0" => "AUTHORIZATION: basic #{Base64.strict_encode64("x-access-token:#{token}")}")
      end
      out, _err, status = Open3.capture3(env, "git", "-C", root, *args)
      raise StructuredTicket::Invalid, "Engineering Git #{args.first} failed (#{status.exitstatus}); original branch preserved" unless status.success?
      out
    end

    def generate!(ticket:)
      root = root!
      File.open(File.join(root, ".git", "nevaeh-authoring.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        relative_parts = PATH.split("/")
        relative_parts.each_index do |index|
          raise StructuredTicket::Invalid, "Engineering output cannot traverse symlinks" if File.symlink?(File.join(root, *relative_parts[0..index]))
        end
        source = ReviewedImplementationTemplateV7a.service_source
        hash = Digest::SHA256.hexdigest(source)
        path = File.join(root, PATH)
        existing = File.file?(path)
        raise StructuredTicket::Invalid, "Existing implementation differs; review required" if existing && Digest::SHA256.file(path).hexdigest != hash
        dirty = run!(root, "status", "--porcelain", "--untracked-files=all").lines
        raise StructuredTicket::Invalid, "Engineering workspace has unrelated changes" unless dirty.all? { |line| line.strip.end_with?(PATH) }
        FileUtils.mkdir_p(File.dirname(path))
        unless existing
          staged_path = File.join(root, ".git", "nevaeh-candidate-#{ticket.id}.rb")
          File.open(staged_path, "wb", 0o600) { |file| file.write(source); file.flush; file.fsync }
          File.rename(staged_path, path)
        end
        Dir.mktmpdir("nevaeh-template-tests-") do |directory|
          test = File.join(directory, "metadata_normalizer_test.rb")
          File.write(test, ReviewedImplementationTemplateV7a.test_source)
          output, _error, status = Open3.capture3({"PATH" => ENV.fetch("PATH"), "HOME" => directory, "LANG" => "C.UTF-8"},
            RbConfig.ruby, "--disable-gems", "-I", File.dirname(path), test, unsetenv_others: true)
          raise StructuredTicket::Invalid, "Reviewed service regression tests failed" unless status.success? && output.include?("PASS")
        end
        run!(root, "add", "--", PATH)
        staged = run!(root, "diff", "--cached", "--name-only", "--", PATH).strip
        unless staged.empty?
          run!(root, "-c", "user.name=Lightek Engineering", "-c", "user.email=engineering@lightekmcg.com", "commit", "--only", "-m", "Implement reviewed metadata normalization for ticket #{ticket.id}", "--", PATH)
        end
        branch = run!(root, "rev-parse", "--abbrev-ref", "HEAD").strip
        begin
          run!(root, "push", "origin", "HEAD:refs/heads/#{branch}", push: true)
        rescue StructuredTicket::Invalid
          run!(root, "fetch", "origin", branch)
          begin
            run!(root, "rebase", "origin/#{branch}")
          rescue StructuredTicket::Invalid
            run!(root, "rebase", "--abort")
            raise StructuredTicket::Invalid, "Engineering source conflict requires review; generated commit retained"
          end
          run!(root, "push", "origin", "HEAD:refs/heads/#{branch}", push: true)
        end
        result = {"path" => PATH, "sha256" => hash, "commit_sha" => run!(root, "rev-parse", "HEAD").strip,
          "branch" => branch, "service_unit_tests_passed" => true, "pushed" => true, "deployed" => false}
        verify!(result)
        result
      end
    end

    def verify!(output)
      root = root!
      raise StructuredTicket::Invalid, "Unexpected generated path" unless output["path"] == PATH
      expected = Digest::SHA256.hexdigest(ReviewedImplementationTemplateV7a.service_source)
      content = run!(root, "show", "#{output.fetch('commit_sha')}:#{PATH}")
      raise StructuredTicket::Invalid, "Committed source verification failed" unless output["sha256"] == expected && Digest::SHA256.hexdigest(content) == expected
      remote_head = run!(root, "ls-remote", "origin", "refs/heads/#{output.fetch('branch')}").split.first
      if remote_head != output["commit_sha"]
        run!(root, "fetch", "origin", output.fetch("branch"))
        run!(root, "merge-base", "--is-ancestor", output.fetch("commit_sha"), remote_head)
        latest = run!(root, "show", "#{remote_head}:#{PATH}")
        raise StructuredTicket::Invalid, "Pushed implementation changed after verification" unless Digest::SHA256.hexdigest(latest) == expected
      end
      true
    end
  end
end
