class SystemJobsController < ApplicationController
  before_action :set_system_job, only: %i[ show edit update destroy ]

  # GET /system_jobs or /system_jobs.json
  def index
    @system_jobs = SystemJob.all
  end

  # GET /system_jobs/1 or /system_jobs/1.json
  def show
  end

  # GET /system_jobs/new
  def new
    @system_job = SystemJob.new
  end

  # GET /system_jobs/1/edit
  def edit
  end

  # POST /system_jobs or /system_jobs.json
  def create
    @system_job = SystemJob.new(system_job_params)

    respond_to do |format|
      if @system_job.save
        format.html { redirect_to @system_job, notice: "System job was successfully created." }
        format.json { render :show, status: :created, location: @system_job }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @system_job.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /system_jobs/1 or /system_jobs/1.json
  def update
    respond_to do |format|
      if @system_job.update(system_job_params)
        format.html { redirect_to @system_job, notice: "System job was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @system_job }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @system_job.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /system_jobs/1 or /system_jobs/1.json
  def destroy
    @system_job.destroy!

    respond_to do |format|
      format.html { redirect_to system_jobs_path, notice: "System job was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_system_job
      @system_job = SystemJob.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def system_job_params
      params.expect(system_job: [ :name, :priority, :job_item_id ])
    end
end
