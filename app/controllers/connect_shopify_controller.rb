class ConnectShopifyController < ActionController::Base
  rescue_from LightekConnect::ShopifyCredentials::Unavailable, with: -> { head :service_unavailable }
  skip_forgery_protection
  def index
    @client_id = LightekConnect::ShopifyCredentials.client_id
    return head :service_unavailable if @client_id.blank?
    response.headers.delete("X-Frame-Options")
    response.headers["Content-Security-Policy"] = "frame-ancestors https://admin.shopify.com https://*.myshopify.com;"
    response.headers["Cache-Control"] = "no-store"
    render layout: false
  end
  def webhook
    return head :unauthorized unless LightekConnect::Shopify.webhook_valid?(request.raw_post, request.headers["X-Shopify-Hmac-Sha256"])
    shop = request.headers["X-Shopify-Shop-Domain"].to_s
    return head :bad_request unless shop.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)
    topic = request.headers["X-Shopify-Topic"]
    case topic
    when "app/uninstalled", "shop/redact"
      LightekConnect::Connection.where(platform: "shopify", revoked_at: nil).where("external_identity LIKE ?", "#{shop}:%").find_each do |connection|
        connection.revoke!
        connection.update!(external_identity: nil) if topic == "shop/redact"
      end
    when "customers/data_request", "customers/redact"
      # The connector requests no Shopify customer data and stores none.
    else
      return head :bad_request
    end
    head :ok
  end
end
