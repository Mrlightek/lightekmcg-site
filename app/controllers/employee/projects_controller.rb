# frozen_string_literal: true
module Employee
  class ProjectsController < Employee::ApplicationController
    before_action :set_project, only: %i[show edit update]

    def index
      authorize! :read, Marlon::Project
      @projects = Marlon::Project.active_first
    end

    def show
      @deliverables = @project.deliverables.order(:due_date)
      @timesheets   = @project.timesheets.order(worked_on: :desc).limit(20)
    end

    def edit; end

    def update
      if @project.update(project_params)
        redirect_to employee_project_path(@project), notice: "Project updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_project
      @project = Marlon::Project.find(params[:id])
      authorize! :read, @project
    end

    def project_params
      params.require(:project).permit(:title, :description, :client_id, :owner_id,
                                       :purchase_id, :status, :start_date, :due_date)
    end
  end
end
