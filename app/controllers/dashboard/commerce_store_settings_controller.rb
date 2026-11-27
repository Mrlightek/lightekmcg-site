# frozen_string_literal: true

class Dashboard::CommerceStoreSettingsController < Dashboard::CommerceBaseController
  before_action :load_store

  def show
    @shipping_promotion = LightekCommerce::ShippingPromotion.settings(@site)
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    @customer_segments = LightekCommerce::CustomerSegment.where(site: @site).order(:name, :id)
    @discount_products = LightekCommerce::Product.visible.where(site: @site)
    @discount_collections = LightekCommerce::Collection.where(site: @site).order(:name, :id)
    @discounts = LightekCommerce::Discount.where(site: @site).includes(:target_product, :target_collection, :customer_segment).order(:id)
    uses = LightekCommerce::DiscountUse.counted.where(discount: @discounts.except(:order))
    pending = uses.where(lightek_commerce_orders: {status: 'pending_payment'})
    settled = uses.where.not(lightek_commerce_orders: {status: 'pending_payment'})
    @pending_discount_counts = pending.group(:discount_id).count
    @settled_discount_counts = settled.group(:discount_id).count
    @settled_discount_values = settled.group(:discount_id).sum(:amount_cents)
  end

  def update
    appearance = params.require(:appearance).permit(*LightekCommerce::StoreAppearance::FIELDS)
    LightekCommerce::StoreAppearance.save!(@site, appearance)
    redirect_to_store('Checkout and account settings saved.')
  rescue LightekCommerce::StoreAppearance::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to_store(error.message, error: true)
  end

  def update_shipping_promotion
    values = params.require(:shipping_promotion).permit(:enabled, :minimum_cents, :maximum_rate_cents, :code)
    LightekCommerce::ShippingPromotion.save!(@site, values)
    redirect_to_store('Free shipping settings saved.')
  rescue LightekCommerce::ShippingPromotion::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to_store(error.message, error: true)
  end

  def update_gift_cards
    enabled = params[:enabled] == '1'
    if enabled && !LightekCommerce::GiftCards.platform_enabled?
      return redirect_to_store('Gift card payments are unavailable on this installation.', error: true)
    end

    @site.with_lock { @site.update!(manifest: @site.manifest.to_h.merge('commerce_gift_cards' => enabled)) }
    redirect_to_store(enabled ? 'Gift cards enabled.' : 'New gift card sales paused. Existing cards can still be redeemed.')
  end

  def gift_liability
    response.headers['Cache-Control'] = 'private, no-store'
    @gift_balances = LightekCommerce::GiftLiability.for_store(@site)
    @generated_at = Time.current
    respond_to do |format|
      format.html
      format.csv do
        send_data LightekCommerce::GiftLiability.summary_csv(@gift_balances, generated_at: @generated_at),
          filename: 'gift-card-balances.csv', type: 'text/csv; charset=utf-8'
      end
    end
  rescue LightekCommerce::GiftLiability::Unavailable => error
    redirect_to_store(error.message, error: true)
  end

  def save_segment
    segments = LightekCommerce::CustomerSegment.where(site: @site)
    segment = request.patch? ? segments.find(params[:id]) : segments.new
    segment.update!(params.require(:segment).permit(:name, :minimum_orders, :maximum_orders, :minimum_net_spend_cents))
    redirect_to_store('Customer segment saved.')
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_store(error.record.errors.full_messages.to_sentence, error: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to_store('A customer segment with this name already exists.', error: true)
  end

  def delete_segment
    segment = LightekCommerce::CustomerSegment.where(site: @site).find(params[:id])
    if segment.destroy
      redirect_to_store('Customer segment deleted.')
    else
      redirect_to_store('Remove this segment from its discounts before deleting it.', error: true)
    end
  end

  def create_discount
    LightekCommerce::Discount.create!(discount_params.merge(site: @site))
    redirect_to_store('Discount created.')
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_store(error.record.errors.full_messages.to_sentence, error: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to_store('This code already exists for your store.', error: true)
  end

  def import_discounts
    file = params[:file]
    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return redirect_to_store('Choose a CSV file to import.', error: true)
    end

    service = LightekCommerce::DiscountCSV
    content = file.read(service::MAX_BYTES + 1).to_s.force_encoding(Encoding::UTF_8)
    count = service.import!(@site, content)
    redirect_to_store("Imported #{count} discount #{'code'.pluralize(count)}.")
  rescue LightekCommerce::DiscountCSV::Invalid => error
    redirect_to_store(error.message, error: true)
  end

  def export_discounts
    response.headers['Cache-Control'] = 'private, no-store'
    send_data LightekCommerce::DiscountCSV.export(@site), filename: 'discount-codes.csv', type: 'text/csv; charset=utf-8'
  end

  def update_discount
    discount = LightekCommerce::Discount.where(site: @site).find(params[:id])
    attrs = params.key?(:discount) ? discount_params : {active: params[:active] == '1'}
    discount.update!(attrs)
    redirect_to_store('Discount updated.')
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_store(error.record.errors.full_messages.to_sentence, error: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to_store('This code already exists for your store.', error: true)
  end

  private

  def discount_params
    params.require(:discount).permit(:name, :code, :kind, :amount, :minimum_cents, :combinable,
      :target_product_id, :target_collection_id, :qualifying_product_id, :qualifying_collection_id,
      :buy_quantity, :get_quantity, :applications_per_order, :reward_type, :customer_segment_id, :starts_at, :ends_at, :usage_limit, :buyer_limit)
  end

  def redirect_to_store(message, error: false)
    redirect_to dashboard_commerce_store_settings_path(site_id: @site.id),
      status: :see_other, flash: {(error ? :alert : :notice) => message}
  end

  def load_store
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    head :forbidden unless @site.tenant == current_user
  end
end
