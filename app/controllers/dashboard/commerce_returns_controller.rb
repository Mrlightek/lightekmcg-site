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
    @refunds = @order.refunds.where.not(merchandise_return_id: nil).index_by(&:merchandise_return_id)
  end

  def label
    pdf = LightekCommerce::ReturnLabels.download!(order: @order, return_id: params[:return_id])
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data pdf, type: 'application/pdf', disposition: 'attachment', filename: "return-#{params[:return_id]}-label.pdf"
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
    when 'upload_label'
      LightekCommerce::ReturnLabels.upload!(order: @order, return_id: id, actor: current_user,
        upload: params[:label_pdf], carrier: params[:carrier], tracking_number: params[:tracking_number])
      'Return label saved.'
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
    LightekCommerce::Refunds::Invalid, LightekCommerce::ReturnLabels::Invalid, Stripe::StripeError => error
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
