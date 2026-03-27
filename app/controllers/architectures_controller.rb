class ArchitecturesController < ApplicationController
  before_action :set_architecture, only: %i[ show edit update destroy ]

  # GET /architectures or /architectures.json
  def index
    @architectures = Architecture.all
  end

  # GET /architectures/1 or /architectures/1.json
  def show
  end

  # GET /architectures/new
  def new
    @architecture = Architecture.new
  end

  # GET /architectures/1/edit
  def edit
  end

  # POST /architectures or /architectures.json
  def create
    @architecture = Architecture.new(architecture_params)

    respond_to do |format|
      if @architecture.save
        format.html { redirect_to @architecture, notice: "Architecture was successfully created." }
        format.json { render :show, status: :created, location: @architecture }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @architecture.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /architectures/1 or /architectures/1.json
  def update
    respond_to do |format|
      if @architecture.update(architecture_params)
        format.html { redirect_to @architecture, notice: "Architecture was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @architecture }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @architecture.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /architectures/1 or /architectures/1.json
  def destroy
    @architecture.destroy!

    respond_to do |format|
      format.html { redirect_to architectures_path, notice: "Architecture was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_architecture
      @architecture = Architecture.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def architecture_params
      params.fetch(:architecture, {})
    end
end
