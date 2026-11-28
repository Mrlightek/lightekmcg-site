# frozen_string_literal: true

class Dashboard::CommerceCollectionsController < Dashboard::CommerceBaseController
  before_action :load_site
  before_action :load_collection, only: %i[edit update destroy]

  def index
    @collections = LightekCommerce::Collection.where(site: @site).order(:name, :id)
  end

  def new
    @collection = LightekCommerce::Collection.new(site: @site)
    load_products
  end

  def create
    @collection = LightekCommerce::Collection.new(collection_params.merge(site: @site))
    save_collection(:new)
  end

  def edit
    load_products
  end

  def update
    @collection.assign_attributes(collection_params)
    save_collection(:edit)
  end

  def destroy
    @collection.destroy!
    redirect_to dashboard_commerce_collections_path(site_id: @site.id), status: :see_other, notice: 'Collection deleted.'
  end

  private

  def save_collection(view)
    if @collection.save
      redirect_to dashboard_commerce_collections_path(site_id: @site.id), status: :see_other, notice: 'Collection saved.'
    else
      load_products
      render view, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @collection.errors.add(:slug, 'is already used in this store')
    load_products
    render view, status: :unprocessable_entity
  end

  def load_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    head :forbidden unless @site.tenant == current_user
  end

  def load_collection
    @collection = LightekCommerce::Collection.where(site: @site).find(params[:id])
  end

  def load_products
    @products = LightekCommerce::Product.where(site: @site).order(:name, :id)
  end

  def collection_params
    attrs = params.require(:collection).permit(:name, :slug, :description, :source, :matching, :published,
      product_ids: [], conditions: %i[field operator value]).to_h
    rows = attrs.fetch('conditions', [])
    rows = rows.values if rows.is_a?(Hash)
    attrs['conditions'] = rows.reject { |condition| condition['field'].blank? }
    attrs
  end
end
