class Dashboard::ConnectShopifySettingsController < ApplicationController
  protect_from_forgery with: :exception
  def update
    values = params.require(:shopify).permit(:client_id, :client_secret)
    LightekConnect::ShopifyCredentials.store!(actor: current_user,
      client_id: values[:client_id], client_secret: values[:client_secret])
    redirect_to dashboard_connect_path, notice: "Shopify credentials saved in Vault. The connector uses them immediately; no environment edit or restart is required."
  rescue Gatekeeper::Hosting::Access::Denied
    head :forbidden
  rescue ArgumentError, LightekConnect::ShopifyCredentials::Unavailable => error
    redirect_to dashboard_connect_path, alert: error.message
  end
end
