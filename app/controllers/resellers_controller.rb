class ResellersController < ApplicationController
  before_action :set_reseller, only: %i[ show edit update destroy ]

  # GET /resellers or /resellers.json
  def index
    @resellers = Reseller.all
  end

  # GET /resellers/1 or /resellers/1.json
  def show
  end

  # GET /resellers/new
  def new
    @reseller = Reseller.new
  end

  # GET /resellers/1/edit
  def edit
  end

  # POST /resellers or /resellers.json
  def create
    @reseller = Reseller.new(reseller_params)

    respond_to do |format|
      if @reseller.save
        format.html { redirect_to @reseller, notice: "Reseller was successfully created." }
        format.json { render :show, status: :created, location: @reseller }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @reseller.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /resellers/1 or /resellers/1.json
  def update
    respond_to do |format|
      if @reseller.update(reseller_params)
        format.html { redirect_to @reseller, notice: "Reseller was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @reseller }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @reseller.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /resellers/1 or /resellers/1.json
  def destroy
    @reseller.destroy!

    respond_to do |format|
      format.html { redirect_to resellers_path, notice: "Reseller was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_reseller
      @reseller = Reseller.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def reseller_params
      params.fetch(:reseller, {})
    end
end
