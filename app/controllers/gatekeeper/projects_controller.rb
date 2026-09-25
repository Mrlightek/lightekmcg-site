module Gatekeeper
  class ProjectsController < ApplicationController
    before_action :set_project, only: %i[show edit update destroy deploy deploy_github healthcheck]

    def index = @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)

    def show
      @operations = @project.gatekeeper_operations.recent_first.limit(25)
    end

    def new
      @project = GatekeeperProject.new(
        gatekeeper_node_id: params[:gatekeeper_node_id],
        branch: "main",
        ruby_version: "3.3.6",
        rails_env: "production",
        app_user: "lightek",
        apache_service_name: "apache2"
      )
    end

    def edit; end

    def create
      @project = GatekeeperProject.new(project_params)
      return redirect_to(gatekeeper_project_path(@project), notice: "Gatekeeper project created.") if @project.save
      render :new, status: :unprocessable_entity
    end

    def update
      return redirect_to(gatekeeper_project_path(@project), notice: "Gatekeeper project updated.") if @project.update(project_params)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @project.destroy!
      redirect_to gatekeeper_projects_path, notice: "Gatekeeper project removed."
    end

    def deploy
      DeployProjectJob.perform_later(
        @project.id,
        requested_by: requester_name,
        parameters: { "branch" => @project.branch }
      )
      redirect_to gatekeeper_project_path(@project), notice: "Deployment queued."
    end

    def deploy_github
      operation = GitHubActionsService.dispatch_deploy!(project: @project, requested_by: requester_name, ref: @project.branch)
      redirect_to gatekeeper_project_path(@project), notice: "GitHub Actions deployment queued as Gatekeeper operation ##{operation.id}."
    rescue Gatekeeper::GitHubActionsService::ConfigurationError, Gatekeeper::GitHubActionsService::DispatchError => e
      redirect_to gatekeeper_project_path(@project), alert: "GitHub deployment could not be queued: #{e.message}"
    end

    def healthcheck
      HealthcheckProjectJob.perform_later(@project.id, requested_by: requester_name)
      redirect_to gatekeeper_project_path(@project), notice: "Healthcheck queued."
    end

    private

    def set_project = @project = GatekeeperProject.find(params[:id])

    def requester_name
      respond_to?(:current_user) && current_user ? "user:#{current_user.id}" : "gatekeeper_dashboard"
    end

    def project_params
      params.expect(gatekeeper_project: [
        :gatekeeper_node_id, :name, :repository, :branch, :domain,
        :app_root, :app_user, :ruby_version, :rails_env,
        :apache_service_name, :sidekiq_service_name
      ])
    end
  end
end
