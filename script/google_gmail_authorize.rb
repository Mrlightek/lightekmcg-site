require "googleauth"
require "webrick"
require "uri"
require "cgi"

CLIENT_ID     = ENV.fetch("GOOGLE_GMAIL_CLIENT_ID")
CLIENT_SECRET = ENV.fetch("GOOGLE_GMAIL_CLIENT_SECRET")

SCOPE = "https://www.googleapis.com/auth/gmail.send"
PORT  = 4567
REDIRECT_URI = "http://127.0.0.1:#{PORT}"

client_id = Google::Auth::ClientId.new(
  CLIENT_ID,
  CLIENT_SECRET
)

authorizer = Google::Auth::UserAuthorizer.new(
  client_id,
  SCOPE,
  nil,
  REDIRECT_URI
)

auth_url = authorizer.get_authorization_url(
  base_url: REDIRECT_URI,
  additional_parameters: {
    "access_type" => "offline"
  }
)

puts
puts "Open this URL in your browser:"
puts
puts auth_url
puts

code = nil

server = WEBrick::HTTPServer.new(
  Port: PORT,
  BindAddress: "127.0.0.1",
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)

server.mount_proc "/" do |req, res|
  incoming_code = req.query["code"]

  if incoming_code
    code ||= incoming_code

    res.status = 200
    res["Content-Type"] = "text/html"
    res.body = <<~HTML
      <html>
        <body>
          <h2>Lightek Mail authorization complete.</h2>
          <p>You can close this window and return to Terminal.</p>
        </body>
      </html>
    HTML

    Thread.new do
      sleep 1
      server.shutdown
    end
  else
    res.status = 204
    res.body = ""
  end
end

trap("INT") { server.shutdown }

Thread.new do
  sleep 1
  system("open", auth_url)
end

server.start

raise "Google did not return an authorization code" if code.nil?

credentials = authorizer.get_credentials_from_code(
  code: code,
  base_url: REDIRECT_URI
)

puts
puts "===== GOOGLE GMAIL AUTH COMPLETE ====="
puts
puts "Refresh token:"
puts credentials.refresh_token
puts
puts "Access token:"
puts credentials.access_token
puts
puts "Expires at:"
puts credentials.expires_at