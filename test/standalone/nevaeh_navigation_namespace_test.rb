# frozen_string_literal: true
require "minitest/autorun"
require "open3"
require "rbconfig"

class NevaehNavigationNamespaceTest < Minitest::Test
  def test_navigation_controller_loads_with_the_actual_dashboard_model
    root = File.expand_path("../..", __dir__)
    script = <<~RUBY
      class ApplicationRecord; end
      module DymondDash
        class ApplicationController; end
      end
      load File.join(ARGV.fetch(0), "app/models/dashboard.rb")
      load File.join(ARGV.fetch(0), "app/controllers/dashboard/nevaeh_navigation_controller.rb")
      abort "Dashboard model changed" unless Dashboard.superclass == ApplicationRecord
      abort "Wrong controller parent" unless Dashboard::NevaehNavigationController.superclass == DymondDash::ApplicationController
      abort "Missing sidebar update" unless Dashboard::NevaehNavigationController.instance_methods(false).include?(:update)
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, "-e", script, root)
    assert status.success?, "Controller failed to load: #{output}#{error}"
  end
end
