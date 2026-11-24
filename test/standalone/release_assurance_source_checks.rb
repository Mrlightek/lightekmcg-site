# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../../app/services/release_assurance/source"

class ReleaseAssuranceSourceTest < Minitest::Test
  Source = ReleaseAssurance::Source

  def setup
    @temporary = Dir.mktmpdir
    @origin = File.join(@temporary, "origin")
    git("init", "--bare", @origin, in_dir: @temporary)
    @checkout = File.join(@temporary, "checkout")
    git("clone", @origin, @checkout, in_dir: @temporary)
    git("checkout", "-b", "develop")
    write("app.txt", "start\n")
    @base = commit("base")
    git("push", "origin", "develop")
    @source = Source.new(origin: @origin)
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_records_exact_heads_and_reassembles_after_branch_moves
    git("checkout", "-b", "first")
    write("first.txt", "first\n")
    first = commit("first")
    git("push", "origin", "HEAD:refs/pull/10/head")
    git("checkout", "-b", "dependent")
    write("dependent.txt", "dependent\n")
    dependent = commit("dependent")
    git("push", "origin", "dependent")
    selectors = Source.selectors("pr:10 branch:dependent")
    assembled = @source.assemble(selectors)

    assert_equal @base, assembled.fetch(:base_sha)
    assert_equal [{
      "selector" => "pr:10", "sha" => first, "includes" => []
    }, {
      "selector" => "branch:dependent", "sha" => dependent, "includes" => ["pr:10"]
    }], assembled.fetch(:sources)

    write("new-content.txt", "moved\n")
    commit("new head")
    git("push", "origin", "dependent")
    ref = "release-candidates/abc12345-12aa-1111-1111-000000000000"
    repinned = @source.assemble(selectors, pinned_base: @base, pinned_sources: assembled.fetch(:sources)) do |dir, sha|
      @source.publish!(dir, sha, ref)
    end
    assert_equal assembled, repinned
    @source.checkout(assembled.fetch(:source_sha), ref) do |dir|
      assert_equal "dependent\n", File.read(File.join(dir, "dependent.txt"))
      refute File.exist?(File.join(dir, "new-content.txt"))
    end
    assert_raises(Source::Invalid) { @source.checkout(first, ref) { flunk "wrong revision" } }
  end

  def test_stops_on_the_conflicting_source
    git("checkout", "-b", "conflicting")
    write("app.txt", "feature\n")
    sha = commit("feature")
    git("push", "origin", "conflicting")
    git("checkout", "develop")
    write("app.txt", "base changed\n")
    commit("develop")
    git("push", "origin", "develop")

    result = @source.assemble(["commit:#{sha}"]) { flunk "conflict was published" }
    assert_equal ["commit:#{sha}"], result.fetch(:conflicts)
    refute result.key?(:source_sha)
  end

  def test_enables_prior_batch_workflows_only_in_msp_candidate
    git("checkout", "-b", "msp")
    Source::MSP_WORKFLOWS.each do |name|
      write(".github/workflows/#{name}.yml", "name: Acceptance\non:\n  workflow_dispatch:\njobs: {}\n")
    end
    head = commit("existing suites")
    Source::MSP.each { |selector| git("push", "origin", "HEAD:refs/pull/#{selector.delete_prefix('pr:')}/head") }

    candidate = @source.assemble(Source::MSP) do |dir, sha|
      Source::MSP_WORKFLOWS.each do |name|
        workflow = git("show", "#{sha}:.github/workflows/#{name}.yml", in_dir: dir)
        assert_includes workflow, 'branches: ["release-candidates/**"]'
      end
    end

    assert_empty candidate.fetch(:conflicts)
    refute_equal head, candidate.fetch(:source_sha)
    refute_includes git("show", "HEAD:.github/workflows/batch-d-acceptance.yml"), "push:"
  end

  def test_rejects_invalid_and_duplicate_selectors
    %w[branch:-wrong branch:a/../b pr:0001 branch:x.lock commit:HEAD branch:release-candidates/test].each do |selector|
      assert_raises(Source::Invalid) { Source.selectors(selector) }
    end
    assert_raises(Source::Invalid) { Source.selectors("pr:1 pr:1") }
  end

  private

  def git(*arguments, in_dir: @checkout)
    output, error, status = Open3.capture3(Source::IDENTITY, "git", "-C", in_dir, *arguments)
    assert status.success?, error
    output.strip
  end

  def write(name, text)
    path = File.join(@checkout, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def commit(message)
    git("add", ".")
    git("commit", "-m", message)
    git("rev-parse", "HEAD")
  end
end
