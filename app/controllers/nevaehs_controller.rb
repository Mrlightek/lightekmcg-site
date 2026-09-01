class NevaehsController < ApplicationController
  before_action :set_nevaeh, only: %i[ show edit update destroy ]

  # GET /nevaehs or /nevaehs.json
  def index
    @nevaehs = Nevaeh.all
  end

  # GET /nevaehs/1 or /nevaehs/1.json
  def show
  end

  # GET /nevaehs/new
  def new
    @nevaeh = Nevaeh.new
  end

  # GET /nevaehs/1/edit
  def edit
  end

  # POST /nevaehs or /nevaehs.json
  def create
    @nevaeh = Nevaeh.new(nevaeh_params)

    respond_to do |format|
      if @nevaeh.save
        format.html { redirect_to @nevaeh, notice: "Nevaeh was successfully created." }
        format.json { render :show, status: :created, location: @nevaeh }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @nevaeh.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /nevaehs/1 or /nevaehs/1.json
  def update
    respond_to do |format|
      if @nevaeh.update(nevaeh_params)
        format.html { redirect_to @nevaeh, notice: "Nevaeh was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @nevaeh }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @nevaeh.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /nevaehs/1 or /nevaehs/1.json
  def destroy
    @nevaeh.destroy!

    respond_to do |format|
      format.html { redirect_to nevaehs_path, notice: "Nevaeh was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_nevaeh
      @nevaeh = Nevaeh.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def nevaeh_params
      params.fetch(:nevaeh, {})
    end
end
