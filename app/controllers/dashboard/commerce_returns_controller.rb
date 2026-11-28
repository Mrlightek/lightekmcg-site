# frozen_string_literal: true

class Dashboard::CommerceReturnsController < Dashboard::CommerceBaseController
  before_action :load_site
  before_action :load_order, except: :index

  def index
    response.headers['Cache-Control'] = 'private, no-store'
    @filter = params[:status].presence || 'open'
    filters = LightekCommerce::MerchandiseReturn::QUEUE_FILTERS
    raise ActionController::BadRequest unless filters.key?(@filter)

    before = params[:before].presence
    raise ActionController::BadRequest if before && !before.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

    @returns = LightekCommerce::MerchandiseReturn.queue(site: @site, filter: @filter, before_id: before&.to_i)
    @more_returns = @returns.size > LightekCommerce::MerchandiseReturn::PAGE_SIZE
    @returns.pop if @more_returns
  end

  def show
    response.headers['Cache-Control'] = 'private, no-store'
    @items = @order.items.includes(:product).select(&:physical_for_fulfillment?).index_by(&:id)
    returns = LightekCommerce::MerchandiseReturn.where(order_id: @order.id)
    @used = returns.counting_against_order.group(:order_item_id).sum(:quantity)
    @returns = returns.order(id: :desc).to_a
    @return_labels = LightekCommerce::ReturnLabel.list_for(@returns)
    @carrier_quotes = LightekShipping::Quote.where(site_id: @site.id, merchandise_return_id: @returns.map(&:id))
      .where('expires_at > :now OR id IN (:selected)', now: Time.current, selected: @returns.filter_map(&:return_shipping_quote_id))
      .includes(:shipment).order(:platform_price_cents).group_by(&:merchandise_return_id)
    @refunds = @order.refunds.where.not(merchandise_return_id: nil).index_by(&:merchandise_return_id)
  end

  def label
    if params[:carrier_label] == '1'
      data, type, extension = LightekCommerce::ReturnShipping.label!(order: @order, return_id: params[:return_id])
    else
      data = LightekCommerce::ReturnLabels.download!(order: @order, return_id: params[:return_id])
      type, extension = 'application/pdf', 'pdf'
    end
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data data, type: type, disposition: 'attachment', filename: "return-#{params[:return_id]}-label.#{extension}"
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
      service.approve!(id, refund_fee_cents: params[:refund_fee_cents])
      'Return approved.'
    when 'reject'
      service.reject!(id)
      'Return rejected.'
    when 'cancel'
      service.cancel!(id)
      'Return canceled.'
    when 'quote_return_shipping'
      package = params.expect(package: %i[weight_lb length_in width_in height_in]).to_h
      LightekCommerce::ReturnShipping.rates!(order: @order, return_id: id, package: package)
      'Return shipping rates are ready.'
    when 'buy_return_shipping'
      url = LightekCommerce::ReturnShipping.purchase!(order: @order, return_id: id, quote_key: params.require(:quote_key),
        email: current_user.email_address, return_url: dashboard_commerce_returns_url(order_id: @order.id, site_id: @site.id))
      return redirect_to url, allow_other_host: true, status: :see_other
    when 'refresh_return_shipping'
      LightekCommerce::ReturnShipping.refresh!(order: @order, return_id: id)
      'Return label status refreshed.'
    when 'upload_label'
      LightekCommerce::ReturnLabels.upload!(order: @order, return_id: id, actor: current_user,
        upload: params[:label_pdf], carrier: params[:carrier], tracking_number: params[:tracking_number])
      'Return label saved.'
    when 'reserve_exchange'
      LightekCommerce::ReturnExchanges.new(order: @order, actor: current_user).reserve!(id, replacement: params[:replacement])
      'Replacement stock reserved.'
    when 'ship_exchange'
      LightekCommerce::ReturnExchanges.new(order: @order, actor: current_user).ship!(id, reference: params[:shipping_reference])
      'Replacement marked as shipped.'
    when 'cancel_exchange'
      LightekCommerce::ReturnExchanges.new(order: @order, actor: current_user).cancel!(id)
      'Exchange canceled and replacement stock released.'
    when 'refund'
      record = LightekCommerce::MerchandiseReturn.where(order_id: @order.id).find(id)
      refund = LightekCommerce::Refunds.issue!(order: @order, merchandise_return_id: record.id,
        amount_cents: params.require(:amount_cents))
      "Refund status: #{refund.status.humanize}."
    when 'receive'
      service.receive!(id, disposition: params[:disposition])
      'Return received.'
    else
      raise ActionController::BadRequest
    end
    redirect_to return_path, notice: notice, status: :see_other
  rescue LightekCommerce::MerchandiseReturns::Invalid, LightekCommerce::InventoryStockStates::Invalid,
    LightekCommerce::Refunds::Invalid, LightekCommerce::ReturnLabels::Invalid, LightekCommerce::ReturnExchanges::Invalid,
    LightekCommerce::ReturnShipping::Invalid, LightekCommerce::StripeCheckout::Unavailable, Stripe::StripeError,
    LightekShipping::Fedex::Unavailable, LightekShipping::Ups::Unavailable, LightekReservations::Federation::Client::Unavailable,
    ArgumentError => error
    redirect_to return_path, alert: error.message, status: :see_other
  end

  private

  def load_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end

  def load_order
    @order = LightekCommerce::Order.receipt_eligible.where(site: @site).find(params.require(:order_id))
    raise ActiveRecord::RecordNotFound unless LightekCommerce::MerchandiseReturns.eligible_order?(@order)
  end

  def return_path
    dashboard_commerce_returns_path(order_id: @order.id, site_id: @site.id)
  end
end
