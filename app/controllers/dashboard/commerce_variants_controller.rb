# frozen_string_literal: true
class Dashboard::CommerceVariantsController < Dashboard::CommerceBaseController
  before_action :load_product
  def create
    @product.with_lock { @product.variants.create!(variant_params) }
    redirect_to edit_dashboard_commerce_product_path(@product, site_id: @site.id), notice: "Option added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_dashboard_commerce_product_path(@product, site_id: @site.id), alert: e.record.errors.full_messages.to_sentence
  end
  def destroy
    @product.with_lock do
      variant = @product.variants.find(params.require(:id))
      variant.update!(active: false)
    end
    redirect_to edit_dashboard_commerce_product_path(@product, site_id: @site.id), notice: "Option disabled."
  end
  private
  def load_product
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    @product = LightekCommerce::Product.where(site: @site).find(params.require(:product_id))
  end
  def variant_params
    params.require(:variant).permit(:name, :sku, :price_cents, :inventory_quantity)
  end
end
