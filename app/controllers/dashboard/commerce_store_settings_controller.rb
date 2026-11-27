# frozen_string_literal: true

class Dashboard::CommerceStoreSettingsController < Dashboard::CommerceBaseController
  before_action :load_store

  def show
    @appearance = LightekCommerce::StoreAppearance.read(@site)
    @discounts = LightekCommerce::Discount.where(site: @site).order(:id)
  end

  def update
    appearance = params.require(:appearance).permit(*LightekCommerce::StoreAppearance::FIELDS)
    LightekCommerce::StoreAppearance.save!(@site, appearance)
    redirect_to_store('Checkout and account settings saved.')
  rescue LightekCommerce::StoreAppearance::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to_store(error.message, error: true)
  end

  def create_discount
    attrs = params.require(:discount).permit(:name, :code, :kind, :amount, :minimum_cents)
    LightekCommerce::Discount.create!(attrs.merge(site: @site))
    redirect_to_store('Discount created.')
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_store(error.record.errors.full_messages.to_sentence, error: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to_store('This code already exists for your store.', error: true)
  end

  def update_discount
    discount = LightekCommerce::Discount.where(site: @site).find(params[:id])
    discount.update!(active: params[:active] == '1')
    redirect_to_store('Discount updated.')
  end

  private

  def redirect_to_store(message, error: false)
    redirect_to dashboard_commerce_store_settings_path(site_id: @site.id),
      status: :see_other, flash: {(error ? :alert : :notice) => message}
  end

  def load_store
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    head :forbidden unless @site.tenant == current_user
  end
end
