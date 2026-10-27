# frozen_string_literal: true
class Dashboard::MarketplaceController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_marketplace_admin!
  before_action :set_listing, only: %i[edit update preview]
  protect_from_forgery with: :exception
  helper MarketplaceHelper
  def index
    @listings = DymondCatalog::MarketplaceListing.includes(offer: :subscription_plan).order(:position, :id)
  end
  def new
    @product = LightekMarketplace::ProductForm.new
    @listing = @product.listing
    @step = 0
  end
  def create
    @product = LightekMarketplace::ProductForm.new(attributes: product_params)
    @listing = @product.listing
    persist(:new)
  end
  def edit
    @product = LightekMarketplace::ProductForm.new(listing: @listing)
    @step = 0
  end
  def update
    @product = LightekMarketplace::ProductForm.new(listing: @listing, attributes: product_params)
    persist(:edit)
  end
  def preview
    @offer = @listing.offer
    @intervals = Array(@offer.available_intervals).map(&:to_s)
    @interval = params[:interval].to_s.presence || @offer.default_interval.to_s
    raise ActionController::BadRequest unless @intervals.include?(@interval)
    @preview = DymondBank::Checkout.preview(offer: @offer, interval: @interval)
    @draft_preview = true
    render "marketplace/show", layout: "marketplace"
  end
  private
  def persist(template)
    @product.trial_days = 0 unless @product.recurring?
    @step = params[:editor_step].to_i.clamp(0, 3)
    action = params[:commit_action].to_s
    if action == "refresh"
      render template
    elsif action == "back"
      @step = [@step - 1, 0].max
      render template
    elsif action == "next" || action.start_with?("step_")
      if @product.navigation_valid?(@step)
        @step = action == "next" ? [@step + 1, 3].min : action.delete_prefix("step_").to_i.clamp(0, 3)
        render template
      else
        render template, status: :unprocessable_entity
      end
    elsif %w[draft publish].include?(action)
      if @product.save(publish: action == "publish", actor: current_user)
        redirect_to main_app.dashboard_marketplace_path,
          notice: action == "publish" ? "Product published in your storefront." : "Product saved as a draft."
      else
        @step = if @product.errors.attribute_names.any? { |k| %i[name description category position].include?(k) }
          0
        elsif @product.errors.attribute_names.any? { |k| %i[price billing setup_fee trial_days].include?(k) }
          1
        else
          2
        end
        render template, status: :unprocessable_entity
      end
    else
      head :bad_request
    end
  end
  def require_marketplace_admin!
    head :forbidden unless current_user&.role == "super_admin"
  end
  def set_listing
    @listing = DymondCatalog::MarketplaceListing.find(params[:id])
  end
  def product_params
    params.require(:marketplace_product).permit(:name, :description, :category, :billing,
      :price, :monthly_price, :annual_price, :setup_fee, :trial_days, :delivery, :blueprint_key, :service_id, :welcome, :position, :revision)
  end
end
