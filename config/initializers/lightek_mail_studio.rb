Rails.application.config.filter_parameters += [:"x-lightek-mail-ingress", :"x-lightek-mail-feedback", :mail_token, :token_digest, :text, :html, :document, :attachments, :variables]
Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method(:lightek_https, LightekMail::HttpsDelivery)
end
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :mail
    feature.label = "Lightek Mail"
    feature.icon = "mail"
    feature.gem_source = "lightek_mail"
    feature.nav_section = :platform
    feature.min_plan = :starter
    feature.nav_items = [{label: "Mail", icon: "mail", path: "main_app.dashboard_mail_path"}]
  end
end
