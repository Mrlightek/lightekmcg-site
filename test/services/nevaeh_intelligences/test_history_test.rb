# frozen_string_literal: true
require "test_helper"
require "digest"
require "json"
require "tmpdir"
require "fileutils"

class NevaehTestHistoryTest < ActiveSupport::TestCase
  def with_report(status: "passed", exit_status: 0)
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      folder = root.join("tmp/nevaeh/test_runs")
      FileUtils.mkdir_p(folder)
      run_id = "20261010T163555-802d787b2ad5"
      log = folder.join("#{run_id}.log")
      log.write("5 runs, 14 assertions, 0 failures, 0 errors, 0 skips\n")
      report = {"schema_version" => 1, "run_id" => run_id, "source" => "nevaeh-test",
        "started_at" => Time.current.iso8601, "finished_at" => Time.current.iso8601,
        "status" => status, "exit_status" => exit_status, "capability" => "studio.project.create",
        "output_path" => "tmp/nevaeh/test_runs/#{run_id}.log", "output_sha256" => Digest::SHA256.file(log).hexdigest,
        "counts" => {"tests" => 5, "assertions" => 14, "failures" => 0, "errors" => 0, "skips" => 0}}
      json = folder.join("#{run_id}.json")
      json.write(JSON.generate(report))
      yield root, json, log, report
    end
  end

  test "imports a real local report and keeps structured results" do
    with_report do |root, file, _log, _raw|
      record = NevaehIntelligences::TestHistory.import!(file, root: root)
      assert_equal "passed", record.status
      assert_equal 5, record.tests_count
      assert_equal 14, record.assertions_count
      assert_equal "studio.project.create", record.capability_slug
      assert_equal 1, NevaehTestRun.where(run_id: record.run_id).count
    end
  end

  test "reimport is idempotent" do
    with_report do |root, file, _log, _raw|
      first = NevaehIntelligences::TestHistory.import!(file, root: root)
      second = NevaehIntelligences::TestHistory.import!(file, root: root)
      assert_equal first.id, second.id
    end
  end

  test "rejects changed output" do
    with_report do |root, file, log, _raw|
      NevaehIntelligences::TestHistory.import!(file, root: root)
      log.write("tampered")
      assert_raises(NevaehIntelligences::TestHistory::InvalidReport) do
        NevaehIntelligences::TestHistory.import!(file, root: root)
      end
    end
  end

  test "rejects inconsistent status" do
    with_report(status: "passed", exit_status: 1) do |root, file, _log, _raw|
      assert_raises(NevaehIntelligences::TestHistory::InvalidReport) do
        NevaehIntelligences::TestHistory.import!(file, root: root)
      end
    end
  end
end
