# frozen_string_literal: true

class Dashboard::CommerceStoreSettingsController < Dashboard::CommerceBaseController
  before_action :load_store

  def show
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    @discount_products = LightekCommerce::Product.visible.where(site: @site)
    @discounts = LightekCommerce::Discount.where(site: @site).includes(:target_product).order(:id)
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

  def update_gift_cards
    enabled = params[:enabled] == '1'
    if enabled && !LightekCommerce::GiftCards.platform_enabled?
      return redirect_to_store('Gift card payments are unavailable on this installation.', error: true)
    end

    @site.with_lock { @site.update!(manifest: @site.manifest.to_h.merge('commerce_gift_cards' => enabled)) }
    redirect_to_store(enabled ? 'Gift cards enabled.' : 'New gift card sales paused. Existing cards can still be redeemed.')
  end

  def create_discount
    LightekCommerce::Discount.create!(discount_params.merge(site: @site))
    redirect_to_store('Discount created.')
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_store(error.record.errors.full_messages.to_sentence, error: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to_store('This code already exists for your store.', error: true)
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
      :target_product_id, :starts_at, :ends_at, :usage_limit, :buyer_limit)
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
