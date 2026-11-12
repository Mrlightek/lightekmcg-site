class Dashboard::HostingPurchasesController < ApplicationController
  protect_from_forgery with: :exception
  def create
    package = HostingPackage.available.find(params.require(:package_id))
    owner = User.find(params[:hosting_owner_id].presence || current_user.id)
    raise Gatekeeper::Hosting::Access::Denied, "Choose an account you manage" unless Gatekeeper::Hosting::Access.manages?(current_user, owner)
    domain = params[:domain].present? ? LightekSettings::SiteDomain.public_hostname!(params[:domain]) : nil
    order = LightekCommerce::InstallationCheckout.reserve!(actor: current_user, product: package.product, checkout_key: params.require(:checkout_key))
    return redirect_to installation_path(order) if order.paid_at?
    order.with_lock do
      if order.hosting_owner_id.present? && order.hosting_owner_id != owner.id
        raise LightekCommerce::InstallationCheckout::Invalid, "This checkout already belongs to a different hosting account"
      end
      order.update!(hosting_owner: owner) if order.hosting_owner_id.blank? && order.payment_reference.blank?
      if order.hosting_domain.present? && domain.present? && order.hosting_domain != domain
        raise LightekCommerce::InstallationCheckout::Invalid, "This checkout already has a different hostname"
      end
      order.update!(hosting_domain: domain) if domain && order.hosting_domain.blank? && order.payment_reference.blank?
    end
    checkout = LightekCommerce::StripeCheckout.start!(order: order, success_url: installation_url(order), cancel_url: hosting_dashboard_servers_url)
    redirect_to checkout.url, allow_other_host: true
  rescue Gatekeeper::Hosting::Access::Denied, LightekCommerce::InstallationCheckout::Invalid, LightekCommerce::OrderPlacement::Invalid,
    LightekCommerce::StripeCheckout::Unavailable, LightekSettings::SiteDomain::Invalid => error
    redirect_to hosting_dashboard_servers_path, alert: error.message
  end
end
