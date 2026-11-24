require "test_helper"

class ItServicesDeviceTelemetryTest < ActiveSupport::TestCase
  test "accepts bounded health metrics" do
    result = ItServices::DeviceTelemetry.normalize!(
      "cpu_percent" => 12.5, "patch_status" => "updates_available")
    assert_equal 12.5, result.fetch("cpu_percent")
  end

  test "rejects command and sensitive arbitrary fields" do
    assert_raises(ArgumentError) do
      ItServices::DeviceTelemetry.normalize!("command" => "rm -rf /")
    end
    assert_raises(ArgumentError) do
      ItServices::DeviceTelemetry.normalize!("process_list" => ["private"])
    end
  end

  test "rejects invalid metric ranges" do
    assert_raises(ArgumentError) { ItServices::DeviceTelemetry.normalize!("cpu_percent" => 101) }
    assert_raises(ArgumentError) { ItServices::DeviceTelemetry.normalize!("disk_percent" => -1) }
  end

  test "rejects unbounded payloads" do
    assert_raises(ArgumentError) { ItServices::DeviceTelemetry.normalize!("backup_status" => "x" * 5000) }
  end
end
