# frozen_string_literal: true
# Explicit presentation-only release for an existing READY customer installation.
# Derives an image from the running application, preserving its data and settings.
require "json"
require "base64"
require "shellwords"
require "net/ssh"
require "timeout"
abort "Production runtime required" unless Rails.env.production?
order = LightekCommerce::Order.find(Integer(ENV.fetch("LIGHTEK_PASSWORD_UI_ORDER_ID")))
abort "Existing READY installation required" unless LightekCommerce::Installations.ready?(order)
request = ProvisioningRequest.find(order.provisioning_request_id)
node = request.gatekeeper_node
actor = User.find_by!(role: "super_admin")
domain = LightekCommerce::Installations.hostname(order)
Gatekeeper::WebsiteDeployment.preview_for_owner_access(node: node, domain: domain, owner: request.owner)
Gatekeeper::Compute::NodeVerificationService.call(request: request, requested_by: actor.email_address)
revision = IO.popen(["git", "rev-parse", "HEAD"], &:read).strip
abort "Invalid revision" unless revision.match?(/\A[0-9a-f]{40}\z/)
paths = %w[app/controllers/passwords_controller.rb app/controllers/sessions_controller.rb app/controllers/registrations_controller.rb app/controllers/dashboard/authentication_branding_controller.rb app/services/lightek_design/authentication_branding.rb app/helpers/lightek_design/authentication_helper.rb config/initializers/lightek_authentication_branding.rb app/views/passwords/edit.html.erb app/views/passwords/new.html.erb app/views/sessions/new.html.erb app/views/registrations/new.html.erb app/views/layouts/auth.html.erb app/views/authentication/_brand.html.erb app/views/authentication/_story.html.erb app/views/dashboard/authentication_branding/edit.html.erb app/views/dashboard/website_designs/index.html.erb app/views/lightek_design/_font_picker.html.erb app/controllers/concerns/lightek_design/website_fonts.rb]
files = paths.to_h { |path| [path, Base64.strict_encode64(Rails.root.join(path).binread)] }
remote = <<~'PYTHON'
  import base64, hashlib, json, os, pathlib, re, subprocess, sys, tempfile, time, urllib.request
  data=json.load(sys.stdin)
  domain=data['domain']; revision=data['revision']
  assert re.fullmatch(r'[a-z0-9][a-z0-9.-]+[a-z0-9]',domain) and re.fullmatch(r'[0-9a-f]{40}',revision)
  root=pathlib.Path('/opt/lightek-sites')/domain
  project='lt_'+hashlib.sha256(domain.encode()).hexdigest()[:16]
  compose=root/'compose.yml'
  def run(args):
      return subprocess.run(args,check=True,capture_output=True,text=True).stdout.strip()
  def dc(*args):
      return run(['docker','compose','--env-file',str(root/'.env'),'-p',project,'-f',str(compose),*args])
  cid=dc('ps','-q','web'); assert cid and '\n' not in cid
  running=json.loads(run(['docker','inspect',cid]))[0]
  assert running['Config']['Labels']['com.docker.compose.project']==project
  base=running['Config']['Image']; assert re.fullmatch(r'(?:lightek-site|lightek-auth-ui):[a-zA-Z0-9_.-]+',base)
  user=running['Config'].get('User') or '0'
  assert re.fullmatch(r'[a-zA-Z0-9_:-]+',user)
  allowed={'app/controllers/concerns/lightek_design/website_fonts.rb', 'app/services/lightek_design/authentication_branding.rb', 'app/controllers/registrations_controller.rb', 'app/views/dashboard/authentication_branding/edit.html.erb', 'app/views/authentication/_story.html.erb', 'app/controllers/dashboard/authentication_branding_controller.rb', 'app/views/layouts/auth.html.erb', 'app/views/dashboard/website_designs/index.html.erb', 'app/views/lightek_design/_font_picker.html.erb', 'app/views/passwords/edit.html.erb', 'app/views/passwords/new.html.erb', 'app/views/registrations/new.html.erb', 'app/views/authentication/_brand.html.erb', 'app/controllers/passwords_controller.rb', 'app/controllers/sessions_controller.rb', 'config/initializers/lightek_authentication_branding.rb', 'app/views/sessions/new.html.erb', 'app/helpers/lightek_design/authentication_helper.rb'}
  assert set(data['files'])==allowed
  image='lightek-auth-ui:'+revision
  with tempfile.TemporaryDirectory(prefix='lightek-auth-ui-') as temp:
      stage=pathlib.Path(temp)
      for name,encoded in data['files'].items():
          path=stage/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(base64.b64decode(encoded,validate=True));path.chmod(0o644)
      dockerfile='FROM '+base+'\nUSER 0\n'
      for name in sorted(allowed): dockerfile+='COPY '+name+' /app/'+name+'\n'
      dockerfile+='USER '+user+'\n'
      (stage/'Dockerfile').write_text(dockerfile)
      run(['docker','build','--network=none','-q','-t',image,str(stage)])
  original=compose.read_text()
  updated,count=re.subn(r'(?m)^(\s*image:\s*)(?:lightek-site:\$\{LIGHTEK_RELEASE\}|lightek-auth-ui:[0-9a-f]{40})\s*$',lambda m:m[1]+image,original)
  assert count==2, 'Unexpected application image configuration'
  backup=root/'backups'/('compose.before-auth-ui-'+revision+'.yml')
  backup.parent.mkdir(exist_ok=True);backup.write_text(original);backup.chmod(0o600)
  try:
      compose.write_text(updated)
      dc('up','-d','--no-deps','web')
      port=running['NetworkSettings']['Ports']['3000/tcp'][0]['HostPort']
      assert port.isdigit()
      verified=False
      for attempt in range(25):
          try:
              req=urllib.request.Request('http://127.0.0.1:'+port+'/passwords/new',headers={'Host':domain,'X-Forwarded-Proto':'https'})
              with urllib.request.urlopen(req,timeout=5) as response:
                  body=response.read().decode()
                  verified=response.status==200 and 'data-auth-layout="lightek"' in body and 'auth-input-plain' in body and 'data-auth-site=' in body
              if verified: break
          except Exception: pass
          time.sleep(2)
      assert verified, 'Password presentation health check failed'
  except Exception:
      compose.write_text(original)
      dc('up','-d','--no-deps','web')
      raise
  dashboard_check = r'''
  require "rack/mock"
  require "action_dispatch/testing/integration"
  site = DymondSite::Site.find_by!(host: ENV.fetch("APP_HOST"))
  owner = site.tenant
  raise "Site administrator missing" unless owner.is_a?(User) && %w[admin super_admin].include?(owner.role)
  row = owner.sessions.create!(user_agent: "Lightek branding acceptance", ip_address: "127.0.0.1")
  begin
    env = Rails.application.env_config.merge(Rack::MockRequest.env_for("https://#{site.host}/"))
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::Request.new(env), {})
    jar.signed[:session_id] = row.id
    browser = ActionDispatch::Integration::Session.new(Rails.application)
    browser.host! site.host
    browser.https!
    browser.get "/dashboard/website/account-branding", params: {site_id: site.id}, headers: {"Cookie" => jar.to_header}
    raise "Customer branding dashboard unavailable" unless browser.response.status == 200 && browser.response.body.include?("Save account branding")
    puts "LIGHTEK_BRANDING_DASHBOARD_OK"
  ensure
    row.destroy!
  end
  '''
  checked = dc('exec','-T','web','bin/rails','runner',dashboard_check)
  assert 'LIGHTEK_BRANDING_DASHBOARD_OK' in checked
  (root/'auth-ui-revision').write_text(revision+'\n')
  print('LIGHTEK_PASSWORD_UI_UPDATED='+json.dumps({'revision':revision,'password_page_verified':True,'branding_dashboard_verified':True}))
PYTHON
operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: "website_password_ui_update", requested_by: actor.email_address,
  parameters: {order_id: order.id, revision: revision, files: paths}, status: "running", started_at: Time.current)
secret = nil
output = String.new
begin
  secret = LightekVault::Service.checkout!(slug: node.metadata.fetch("node_credential_secret_slug"), consumer: Gatekeeper::WebsiteDeployment::CONSUMER,
    purpose: "node_bootstrap", requested_by: actor.email_address, gatekeeper_operation_id: operation.id)
  status = nil
  Net::SSH.start(node.ip_address, node.ssh_user, port: node.ssh_port, password: secret.fetch("root_password"),
    non_interactive: true, verify_host_key: :accept_new, timeout: 20) do |ssh|
    ssh.open_channel do |channel|
      channel.exec(Shellwords.join(["python3", "-c", remote])) do |ch, success|
        raise "Presentation release rejected" unless success
        ch.send_data(JSON.generate(domain: domain, revision: revision, files: files)); ch.eof!
      end
      channel.on_data { |_ch, data| raise "Unexpected response" if output.bytesize + data.bytesize > 65_536; output << data }
      channel.on_extended_data { |_ch, _type, _data| }
      channel.on_request("exit-status") { |_ch, data| status = data.read_long }
    end
    Timeout.timeout(180) { ssh.loop }
  end
  raise "Presentation release failed" unless status == 0 && output.include?("LIGHTEK_PASSWORD_UI_UPDATED=")
  operation.update!(status: "succeeded", completed_at: Time.current, exit_status: 0, result: {revision: revision, password_page_verified: true, branding_dashboard_verified: true})
  puts JSON.generate(password_ui_updated: true, revision: revision, order_id: order.id)
rescue StandardError => error
  operation.update!(status: "failed", completed_at: Time.current, error_class: error.class.name, error_message: "Password UI update failed; review target health")
  puts JSON.generate(password_ui_updated: false, error_class: error.class.name)
  exit 1
ensure
  secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  output.clear
end
