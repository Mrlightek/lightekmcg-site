module Lightek
  # Also covers mounted engine controllers that have their own base class.
  class PwaMemberGuard
    def initialize(app) = @app = app
    def call(env)
      if LightekPwa::SourceRuntime.member? && !LightekPwa::SourceRuntime.allowed_request?(ActionDispatch::Request.new(env))
        return [403, {'content-type'=>'application/json', 'cache-control'=>'no-store'}, [JSON.generate(error: 'This shared backend hosts member content. Manage infrastructure and services from central Lightek.')]]
      end
      @app.call(env)
    end
  end
end
