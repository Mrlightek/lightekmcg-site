module Lightek
  class PwaMigrationGuard
    def initialize(app) = @app = app
    def call(env)
      if File.exist?(File.join(Dir.pwd, 'tmp/pwa-migration.lock')) && !env['PATH_INFO'].start_with?('/lightek/', '/up', '/__lightek/')
        return [503, {'content-type'=>'text/plain', 'cache-control'=>'no-store', 'retry-after'=>'30'}, ['Your backend is moving. Please retry shortly.']]
      end
      @app.call(env)
    end
  end
end
