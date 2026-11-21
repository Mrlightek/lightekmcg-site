# frozen_string_literal: true

module NevaehOs
  module HostingActions
    INPUTS = {
      'hosting.server.list' => {},
      'hosting.server.status' => {'node_id'=>:id},
      'hosting.fleet.rollout.list' => {},
      'hosting.fleet.rollout.status' => {'rollout_id'=>:id},
      'hosting.fleet.rollout.control' => {'rollout_id'=>:id, 'operation'=>10, 'confirmed'=>:confirmation}
    }.transform_values(&:freeze).freeze

    module_function

    def authorize!(actor, intent, values)
      case intent
      when 'hosting.server.list', 'hosting.server.status'
        nodes = server_scope(actor)
        intent == 'hosting.server.list' ? nodes : nodes.find(values.fetch('node_id'))
      else
        authorize_fleet!(actor)
        intent == 'hosting.fleet.rollout.list' ? GatekeeperRollout.all : GatekeeperRollout.find(values.fetch('rollout_id'))
      end
    end

    def server_scope(actor)
      Gatekeeper::Hosting::Access.nodes(actor)
    rescue Gatekeeper::Hosting::Access::Denied => error
      raise ArgumentError, error.message
    end

    def authorize_fleet!(actor)
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
    rescue Gatekeeper::Fleet::Rollouts::Invalid => error
      raise ArgumentError, error.message
    end

    def perform!(intent, target, values)
      case intent
      when 'hosting.server.list'
        SpecialistTasks.summary(target, %w[id name status updated_at])
      when 'hosting.server.status'
        target.attributes.slice('id', 'name', 'status', 'updated_at').merge(
          'links'=>[{'label'=>'Open server', 'url'=>"/dashboard/servers/#{target.id}"}])
      when 'hosting.fleet.rollout.list'
        SpecialistTasks.summary(target, %w[id gatekeeper_release_id status scheduled_at])
      when 'hosting.fleet.rollout.status'
        rollout_receipt(target)
      when 'hosting.fleet.rollout.control'
        operation = values.fetch('operation')
        if operation == 'start'
          Gatekeeper::Fleet::Rollouts.start!(target)
        else
          Gatekeeper::Fleet::Rollouts.control!(target, operation)
        end
        rollout_receipt(target.reload)
      end
    rescue Gatekeeper::Fleet::Rollouts::Invalid => error
      raise ArgumentError, error.message
    end

    def rollout_receipt(rollout)
      rollout.attributes.slice('id', 'gatekeeper_release_id', 'status', 'scheduled_at').merge(
        'targets_by_status'=>rollout.gatekeeper_update_targets.group(:status).count,
        'links'=>[{'label'=>'Open rollout', 'url'=>"/dashboard/infrastructure/updates/#{rollout.id}"}])
    end
  end
end
