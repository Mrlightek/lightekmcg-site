module Lightek
  # Also covers mounted engine controllers that have their own base class.
  class PwaMemberGuard
    def initialize(app) = @app = app
    def call(env)
      if LightekPwa::SourceRuntime.shared?
        site = LightekPwa::SiteContext.resolve(ActionDispatch::Request.new(env).host)
        return LightekPwa::SourceRuntime.with_site(site) { guarded_call(env) }
      end
      guarded_call(env)
    rescue ActiveRecord::RecordNotFound
      [404, {'content-type'=>'application/json', 'cache-control'=>'no-store'}, [JSON.generate(error: 'Unknown shared hosting account')]]
    end
    def guarded_call(env)
      if LightekPwa::SourceRuntime.member? && !LightekPwa::SourceRuntime.allowed_request?(ActionDispatch::Request.new(env))
        status = LightekPwa::SourceRuntime.frozen? ? 503 : 403
        return [status, {'content-type'=>'application/json', 'cache-control'=>'no-store'}, [JSON.generate(error: status == 503 ? 'Your account is moving to dedicated hosting. Please retry shortly.' : 'This shared backend hosts member content. Manage infrastructure and services from central Lightek.')]]
      end
      @app.call(env)
    end
  end
end
