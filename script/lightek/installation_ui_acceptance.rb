# frozen_string_literal: true
# Live, read-only UI checks for an existing installation. No payment, checkout,
# allocation or password change is performed. Temporary login sessions are removed.
require "json"
require "net/http"
require "uri"
require "nokogiri"
require "rack/mock"
raise "Production runtime required" unless Rails.env.production?

class InstallationUiHttp
  attr_reader :origin
  def initialize(origin, cookie = nil)
    @origin = URI(origin)
    @cookies = {}
    cookie.to_s.split(/;\s*/).each { |entry| key, value = entry.split("=", 2); @cookies[key] = value if value }
  end
  def call(path, data: nil)
    uri = URI.join(@origin.to_s, path)
    raise "Unexpected destination" unless uri.scheme == "https" && uri.host == @origin.host
    req = data ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    req["Cookie"] = @cookies.map { |key, value| "#{key}=#{value}" }.join("; ")
    req["User-Agent"] = "Mozilla/5.0 LightekInstallationAcceptance"
    req["Accept"] = "text/html,application/json"
    if data
      req["Origin"] = @origin.to_s
      req["Referer"] = "#{@origin}/my/installations"
      req.set_form_data(data)
    end
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 45) { |http| http.request(req) }
    response.get_fields("set-cookie").to_a.each do |line|
      key, value = line.split(";", 2).first.split("=", 2)
      @cookies[key] = value if value
    end
    response
  end
end

sessions = []
fixture = nil
result = {customer_list: false, customer_status: false, dashboard_controls: false,
  native_password_setup_form: false, browser_form_csrf: false, cross_account_access_denied: false, public_site: false, pwa_entry: false}
begin
  order = LightekCommerce::Order.find(Integer(ENV.fetch("LIGHTEK_ACCEPTANCE_ORDER_ID", "1")))
  raise "Existing READY installation required" unless LightekCommerce::Installations.ready?(order)
  actor = User.find_by!(email_address: order.customer_email)
  origin = "https://#{ENV.fetch('APP_HOST', 'lightekmcg.com')}"
  signer = lambda do |user|
    row = user.sessions.create!(user_agent: "Lightek installation UI acceptance", ip_address: "127.0.0.1")
    sessions << row
    env = Rails.application.env_config.merge(Rack::MockRequest.env_for("#{origin}/"))
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::Request.new(env), {})
    jar.signed[:session_id] = row.id
    jar.to_header
  end
  stage = "source_session"
  client = InstallationUiHttp.new(origin, signer.call(actor))
  stage = "customer_list"
  index = client.call("/my/installations")
  raise "Customer list failed" unless index.code == "200" && index.body.include?("My Applications")
  result[:customer_list] = true
  stage = "customer_status"
  status = client.call("/my/installations/#{order.id}.json")
  data = JSON.parse(status.body)
  raise "Customer status failed" unless status.code == "200" && data["id"] == order.id && data["ready"] == true
  raise "Private fields leaked" if data.keys.any? { |key| key.match?(/password|credential|token|secret/) }
  result[:customer_status] = true
  stage = "customer_setup_page"
  page = client.call("/my/installations/#{order.id}")
  raise "Setup page failed" unless page.code == "200" && page.body.include?("Set or reset my password")
  raise "Browser form referrer policy blocks same-origin CSRF" unless page["referrer-policy"] == "same-origin"
  form = Nokogiri::HTML(page.body).at_css("form[action='/my/installations/#{order.id}/access']")
  csrf = form&.at_css('input[name="authenticity_token"]')&.[]("value")
  raise "Setup page has no CSRF protection" unless csrf.present?
  stage = "password_handoff"
  access = client.call("/my/installations/#{order.id}/access", data: {authenticity_token: csrf})
  raise "Password setup did not redirect" unless access.code == "303"
  result[:browser_form_csrf] = true
  destination = URI(access["location"])
  domain = LightekCommerce::Installations.hostname(order)
  raise "Password setup destination mismatch" unless destination.scheme == "https" && destination.host == domain && destination.path.match?(%r{\A/passwords/[^/]+/edit\z})
  # Use a separate cookie jar; the control-plane session never reaches the client.
  target = InstallationUiHttp.new("https://#{domain}")
  stage = "native_password_form"
  setup = target.call(destination.request_uri)
  fields = Nokogiri::HTML(setup.body)
  raise "Native password setup is unavailable" unless setup.code == "200" && fields.at_css('input[name="password"]') && fields.at_css('input[name="password_confirmation"]')
  raise "Password setup is missing its customer design" unless fields.at_css('body[data-auth-layout="lightek"]') && fields.at_css('label[for="password_confirmation"]') && setup.body.include?("Save password &amp; continue")
  brand = fields.at_css('.auth-wordmark')&.text&.strip
  raise "Installation branding is unavailable" unless brand.present? && fields.at_css('body[data-auth-site]')&.[]("data-auth-site").present?
  ["/session/new", "/passwords/new", "/sign_up"].each do |path|
    branded_page = target.call(path)
    branded_fields = Nokogiri::HTML(branded_page.body)
    raise "Account screen branding mismatch" unless branded_page.code == "200" && branded_fields.at_css('.auth-wordmark')&.text&.strip == brand
    raise "Platform placeholder remains" if path == "/session/new" && branded_fields.at_css('input[name="email_address"]')&.[]("placeholder") != "you@example.com"
  end
  result[:authentication_branding] = true
  result[:native_password_setup_form] = true
  home = target.call("/")
  result[:public_site] = home.code == "200"
  result[:pwa_entry] = client.call("/lightek/bootstrap-adapter.js").body.include?("/my/installations")
  stage = "operator_dashboard"
  operator = User.find_by!(role: "super_admin")
  operator_client = operator == actor ? client : InstallationUiHttp.new(origin, signer.call(operator))
  if operator
    dashboard = operator_client.call("/dashboard/installations")
    result[:dashboard_controls] = dashboard.code == "200" && dashboard.body.include?("Account setup &amp; access")
    source_site = order.site
    branding_dashboard = operator_client.call("/dashboard/website/account-branding?site_id=#{source_site.id}")
    raise "Account branding dashboard unavailable" unless branding_dashboard.code == "200" && branding_dashboard.body.include?("Save account branding")
    result[:branding_dashboard] = true
  end
  stage = "client_access_isolation"
  fixture = User.create!(email_address: "installation-ui-#{SecureRandom.hex(10)}@example.invalid",
    first_name: "Installation", last_name: "Acceptance", role: "client", password: SecureRandom.urlsafe_base64(36))
  other = InstallationUiHttp.new(origin, signer.call(fixture))
  own = other.call("/my/installations")
  raise "Ordinary client cannot open My Applications" unless own.code == "200"
  denied = other.call("/my/installations/#{order.id}.json")
  csrf_other = Nokogiri::HTML(own.body).at_css('meta[name="csrf-token"]')&.[]("content")
  denied_access = other.call("/my/installations/#{order.id}/access", data: {authenticity_token: csrf_other})
  result[:cross_account_access_denied] = denied.code == "404" && denied_access.code == "404"
  result[:pass] = result.values.all? { |value| value == true }
rescue StandardError => error
  result[:error_class] = error.class.name
  result[:failed_at] = stage
  result[:pass] = false
ensure
  sessions.each { |row| row.destroy! if row.persisted? }
  if fixture&.persisted?
    raise "Refusing unexpected fixture cleanup" unless fixture.email_address.start_with?("installation-ui-") && fixture.email_address.end_with?("@example.invalid")
    fixture.profile&.destroy!
    fixture.destroy!
  end
end
puts JSON.pretty_generate(result)
exit(result[:pass] ? 0 : 1)
