class JobItemsController < ApplicationController
  before_action :set_job_item, only: %i[ show edit update destroy ]

  # GET /job_items or /job_items.json
  def index
    @job_items = JobItem.all
  end

  # GET /job_items/1 or /job_items/1.json
  def show
  end

  # GET /job_items/new
  def new
    @job_item = JobItem.new
  end

  # GET /job_items/1/edit
  def edit
  end

  # POST /job_items or /job_items.json
  def create
    @job_item = JobItem.new(job_item_params)

    respond_to do |format|
      if @job_item.save
        format.html { redirect_to @job_item, notice: "Job item was successfully created." }
        format.json { render :show, status: :created, location: @job_item }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @job_item.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /job_items/1 or /job_items/1.json
  def update
    respond_to do |format|
      if @job_item.update(job_item_params)
        format.html { redirect_to @job_item, notice: "Job item was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @job_item }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @job_item.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /job_items/1 or /job_items/1.json
  def destroy
    @job_item.destroy!

    respond_to do |format|
      format.html { redirect_to job_items_path, notice: "Job item was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_job_item
      @job_item = JobItem.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def job_item_params
      params.expect(job_item: [ :title, :description ])
    end
end
