class Dashboard::ManagedDnsController < ApplicationController
  include LightekIdentity::SensitiveSession
  layout "installations"
  protect_from_forgery with: :exception

  before_action :load_order
  before_action :require_sensitive_session!, except: :show
  rate_limit to: 20, within: 1.minute

  rescue_from LightekManagedDns::Enrollment::Invalid, LightekManagedDns::Cloudflare::Unavailable, with: :show_error

  def show
    @records = @enrollment&.records(provider) || []
  rescue LightekManagedDns::Cloudflare::Unavailable => error
    @records = []
    @records_error = error.message
  ensure
    @provider&.close
  end

  def create
    raise LightekManagedDns::Enrollment::Invalid, "Confirm the domain owner authorized managed DNS." unless params[:consent] == "1"
    LightekManagedDns::Enrollment.request!(order: @order, actor: current_user)
    redirect_to path, notice: "Managed DNS requested.", status: :see_other
  end

  def stage
    enrollment.stage!(actor: current_user, provider: provider, zone_id: params.require(:zone_id).strip)
    redirect_to path, notice: "Zone staged for record review.", status: :see_other
  ensure
    @provider&.close
  end

  def approve
    raise LightekManagedDns::Enrollment::Invalid, "Confirm that you reviewed the record migration and DNSSEC." unless params[:reviewed] == "1"
    enrollment.approve!(actor: current_user, provider: provider)
    redirect_to path, notice: "Nameserver instructions are ready.", status: :see_other
  ensure
    @provider&.close
  end

  def verify
    enrollment.verify!(provider: provider)
    redirect_to path, notice: "Lightek nameservers and the website address are verified.", status: :see_other
  ensure
    @provider&.close
  end

  def withdraw
    enrollment.withdraw!
    redirect_to path, notice: "Managed DNS request withdrawn.", status: :see_other
  end

  private

  def load_order
    response.headers["Cache-Control"] = "private, no-store"
    return head :forbidden if Current.session&.connect_delegation.present?

    @order = LightekCommerce::Installations.instance_orders.find(params.require(:installation_id))
    owner = LightekManagedDns::Enrollment.owner_for(@order)
    @domain = LightekManagedDns::Enrollment.domain_for(@order)
    raise ActiveRecord::RecordNotFound unless owner && @domain && Gatekeeper::Hosting::Access.manages?(current_user, owner)

    @enrollment = LightekManagedDns::Enrollment.find_by(order: @order)
    if @enrollment && (@enrollment.owner_id != owner.id || @enrollment.domain != @domain)
      raise ActiveRecord::RecordNotFound
    end
  end

  def operator? = Gatekeeper::Hosting::Access.super_admin?(current_user)
  helper_method :operator?

  def enrollment = @enrollment || raise(ActiveRecord::RecordNotFound)
  def provider = @provider ||= LightekManagedDns::Cloudflare.new(current_user)
  def path = installation_managed_dns_path(@order)

  def show_error(error)
    redirect_to path, alert: error.message, status: :see_other
  end
end
