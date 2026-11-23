# frozen_string_literal: true

class Dashboard::CommunicationsServicesController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  before_action :require_super_admin!
  before_action :find_service, only: %i[show update]

  def index
    @services = LightekCommunications::Service.includes(subscription: :order).order(created_at: :desc, id: :desc).limit(100)
    @orders = LightekCommerce::Order.visible.joins(:commerce_subscription, :items)
      .where(status: %w[paid fulfilled], purpose: "purchase")
      .where("lightek_commerce_order_items.purchase_snapshot ->> 'communications_kind' IN (?)",
        LightekCommerce::Product::COMMUNICATIONS_SLUGS.values)
      .where.not(lightek_commerce_subscriptions: { id: LightekCommunications::Service.select(:subscription_id) })
      .distinct.order(id: :desc).limit(30)
  end

  def show
    @subscription = @service.subscription
    @receipt = LightekCommunications::Fulfillment.billing_receipt(@subscription)
    @events = @service.events.includes(:operator).order(id: :desc).limit(30)
  end

  def create
    order = LightekCommerce::Order.visible.find(params.require(:order_id))
    service = LightekCommunications::Fulfillment.register!(order: order, operator: current_user)
    redirect_to dashboard_communications_service_path(service), status: :see_other, notice: "Provisioning record is ready."
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_communications_services_path, status: :see_other, alert: "The order was not found."
  rescue LightekCommunications::Fulfillment::Invalid => error
    redirect_to dashboard_communications_services_path, status: :see_other, alert: error.message
  end

  def carrier
    @configured = LightekCommunications::VoipMs.configured?
  end

  def save_carrier
    carrier = params.require(:carrier).permit(:email, :password)
    LightekCommunications::VoipMs.save!(operator: current_user, email: carrier[:email], password: carrier[:password])
    redirect_to carrier_dashboard_communications_services_path, status: :see_other, notice: "Voice carrier connection saved."
  rescue LightekCommunications::VoipMs::Unavailable => error
    redirect_to carrier_dashboard_communications_services_path, status: :see_other, alert: error.message
  end

  def verify_carrier
    fields = params.require(:carrier).permit(:sip_account, :phone_number)
    LightekCommunications::VoipMs.verify!(operator: current_user, account: fields[:sip_account], phone_number: fields[:phone_number])
    message = fields[:phone_number].present? ? "The carrier confirmed the number route and SIP registration." : "The carrier confirmed SIP registration."
    redirect_to carrier_dashboard_communications_services_path, status: :see_other, notice: message
  rescue LightekCommunications::VoipMs::Unavailable => error
    redirect_to carrier_dashboard_communications_services_path, status: :see_other, alert: error.message
  end

  def update
    fields = params.require(:service).permit(:operation, :suspension_reference,
      *LightekCommunications::Fulfillment::TEST_EVIDENCE.fetch(@service.kind).keys)
    LightekCommunications::Fulfillment.transition!(service: @service, action: fields[:operation],
      operator: current_user, evidence: fields)
    redirect_to dashboard_communications_service_path(@service), status: :see_other, notice: "Service evidence recorded."
  rescue LightekCommunications::Fulfillment::Invalid, LightekCommunications::VoipMs::Unavailable => error
    redirect_to dashboard_communications_service_path(@service), status: :see_other, alert: error.message
  end

  private

  def require_super_admin!
    response.headers["Cache-Control"] = "no-store, private"
    LightekCommunications::Fulfillment.check_operator!(current_user)
  rescue LightekCommunications::Fulfillment::Invalid
    head :forbidden
  end

  def find_service
    @service = LightekCommunications::Service.find(params[:id])
  end
end
