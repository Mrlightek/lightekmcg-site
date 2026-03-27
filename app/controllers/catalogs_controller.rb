class CatalogsController < ApplicationController
  before_action :set_catalog, only: %i[ show edit update destroy ]

  # GET /catalogs or /catalogs.json
  def index
    @catalogs = Catalog.all
  end

  # GET /catalogs/1 or /catalogs/1.json
  def show
  end

  # GET /catalogs/new
  def new
    @catalog = Catalog.new
  end

  # GET /catalogs/1/edit
  def edit
  end

  # POST /catalogs or /catalogs.json
  def create
    @catalog = Catalog.new(catalog_params)

    respond_to do |format|
      if @catalog.save
        format.html { redirect_to @catalog, notice: "Catalog was successfully created." }
        format.json { render :show, status: :created, location: @catalog }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @catalog.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /catalogs/1 or /catalogs/1.json
  def update
    respond_to do |format|
      if @catalog.update(catalog_params)
        format.html { redirect_to @catalog, notice: "Catalog was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @catalog }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @catalog.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /catalogs/1 or /catalogs/1.json
  def destroy
    @catalog.destroy!

    respond_to do |format|
      format.html { redirect_to catalogs_path, notice: "Catalog was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_catalog
      @catalog = Catalog.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def catalog_params
      params.fetch(:catalog, {})
    end
end
