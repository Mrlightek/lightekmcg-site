# frozen_string_literal: true
module LightekCommerce
  class InstanceReadyMailer < ApplicationMailer
    def ready(order_id)
      @order = Order.find(order_id)
      raise ArgumentError, "Installation is not ready" unless @order.provisioned_at?
      @hostname = "client-#{@order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}"
      buyer = User.find_by(email_address: @order.customer_email)
      if buyer&.password_setup_required?
        minutes = AccountSetupSetting.link_minutes
        @setup_link_lifetime = AccountSetupSetting::LIFETIMES.fetch(minutes)
        @account_setup_url = edit_account_setup_url(buyer.password_setup_token(link_minutes: minutes))
      end
      mail(to: @order.customer_email, subject: "Your Lightek installation is ready")
    end
  end
end
