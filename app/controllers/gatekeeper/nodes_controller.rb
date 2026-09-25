module Gatekeeper
  class NodesController < ApplicationController
    before_action :set_node, only: %i[show edit update destroy]

    def index = @nodes = GatekeeperNode.order(:name)
    def show = @projects = @node.gatekeeper_projects.order(:name)
    def new = @node = GatekeeperNode.new(ssh_user: "root", ssh_port: 22)
    def edit; end

    def create
      @node = GatekeeperNode.new(node_params)
      return redirect_to(gatekeeper_node_path(@node), notice: "Gatekeeper node created.") if @node.save
      render :new, status: :unprocessable_entity
    end

    def update
      return redirect_to(gatekeeper_node_path(@node), notice: "Gatekeeper node updated.") if @node.update(node_params)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @node.destroy!
      redirect_to gatekeeper_nodes_path, notice: "Gatekeeper node removed."
    end

    private

    def set_node = @node = GatekeeperNode.find(params[:id])

    def node_params
      params.expect(gatekeeper_node: [
        :name, :hostname, :ip_address, :ssh_user, :ssh_port,
        :ssh_key_path, :provider, :provider_id, :region
      ])
    end
  end
end
