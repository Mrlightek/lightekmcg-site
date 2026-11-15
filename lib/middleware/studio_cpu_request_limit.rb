require "stringio"

# Runs before Rails parameter parsing, which can otherwise buffer an oversized
# JSON body before the controller gets a chance to validate it.
class StudioCpuRequestLimit
  LIMIT = 1_048_576
  PREFIX = "/api/reservations/federation/studio/cpu"
  def initialize(app) = @app = app
  def call(env)
    if env.fetch("PATH_INFO", "").start_with?(PREFIX)
      return rejected if env.fetch("CONTENT_LENGTH", "0").to_i > LIMIT
      input = env["rack.input"]
      if input
        body = input.read(LIMIT + 1).to_s
        return rejected if body.bytesize > LIMIT
        env["rack.input"] = StringIO.new(body)
        env["CONTENT_LENGTH"] = body.bytesize.to_s
      end
    end
    @app.call(env)
  end
  private
  def rejected
    body = '{"error":"Remote CPU request exceeds 1 MiB"}'
    [413, {"content-type" => "application/json", "cache-control" => "no-store", "content-length" => body.bytesize.to_s}, [body]]
  end
end
