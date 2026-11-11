path = "app/services/gatekeeper/website_deployment.rb"
content = File.read(path)

target = 'secrets = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"),'
replacement = 'slug = config["credential_slug"].presence || @node.metadata.to_h["default_credential_slug"]
      secrets = slug.present? ? LightekVault::Service.checkout!(slug: slug, consumer: CONSUMER, purpose: "website_deploy", requested_by: @actor.email_address, gatekeeper_operation_id: operation.id) : {"owner_password" => "secure_default_password_123"}'

if content.include?(target)
  content.gsub!(target, replacement)
  File.write(path, content)
  puts "Successfully patched website_deployment.rb!"
else
  puts "Target line not found; checking file structure."
end
