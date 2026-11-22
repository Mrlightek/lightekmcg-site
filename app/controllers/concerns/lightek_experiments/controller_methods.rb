# frozen_string_literal: true

module LightekExperiments
  module ControllerMethods
    extend ActiveSupport::Concern

    included do
      helper_method :experiment_text
    end

    private

    def experiment_text(surface, default, site: @site, target: '')
      experiment_experience(site).copy(surface: surface, target: target, default: default)
    end

    def record_platform_experiment(event, record, site: @site)
      experiment_experience(site).record(event, record)
    end

    def experiment_experience(site)
      Experience.new(site: site, request: request, response: response, cookies: cookies)
    end
  end
end
