# frozen_string_literal: true
Rails.application.config.to_prepare do
  target = Marlon::Provisioning.singleton_class
  bridge = LightekMarketplace::ProvisioningBridge
  target.prepend(bridge) unless target.ancestors.include?(bridge)
end
Rails.application.config.to_prepare do
  lifecycle = LightekMarketplace::AccessLifecycle
  DymondBank::Subscription.prepend(lifecycle) unless DymondBank::Subscription.ancestors.include?(lifecycle)
end
