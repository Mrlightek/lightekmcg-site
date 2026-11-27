# frozen_string_literal: true

class Dashboard::CommerceReturnsController < Dashboard::CommerceBaseController
  before_action :load_order

  def show
    response.headers['Cache-Control'] = 'private, no-store'
    @items = @order.items.includes(:product).select(&:physical_for_fulfillment?).index_by(&:id)
    returns = LightekCommerce::MerchandiseReturn.where(order_id: @order.id)
    @used = returns.counting_against_order.group(:order_item_id).sum(:quantity)
    @returns = returns.order(id: :desc)
  end

  def create
    service = LightekCommerce::MerchandiseReturns.new(order: @order, actor: current_user)
    service.request!(item_id: params[:item_id], quantity: params[:quantity],
      reason: params[:reason], request_key: params[:request_key])
    redirect_to return_path, notice: 'Return request recorded.', status: :see_other
  rescue LightekCommerce::MerchandiseReturns::Invalid => error
    redirect_to return_path, alert: error.message, status: :see_other
  end

  def change
    service = LightekCommerce::MerchandiseReturns.new(order: @order, actor: current_user)
    id = params[:return_id]
    notice = case params[:operation]
    when 'approve'
      service.approve!(id)
      'Return approved.'
    when 'reject'
      service.reject!(id)
      'Return rejected.'
    when 'cancel'
      service.cancel!(id)
      'Return canceled.'
    when 'receive'
      service.receive!(id, disposition: params[:disposition])
      'Return received.'
    else
      raise ActionController::BadRequest
    end
    redirect_to return_path, notice: notice, status: :see_other
  rescue LightekCommerce::MerchandiseReturns::Invalid, LightekCommerce::InventoryStockStates::Invalid => error
    redirect_to return_path, alert: error.message, status: :see_other
  end

  private

  def load_order
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    @order = LightekCommerce::Order.receipt_eligible.where(site: @site).find(params.require(:order_id))
    raise ActiveRecord::RecordNotFound unless LightekCommerce::MerchandiseReturns.eligible_order?(@order)
  end

  def return_path
    dashboard_commerce_returns_path(order_id: @order.id, site_id: @site.id)
  end
end
