# frozen_string_literal: true

module NevaehOs
  module HostingActions
    INPUTS = {
      'hosting.server.list' => {},
      'hosting.server.status' => {'node_id'=>:id},
      'hosting.project.healthcheck' => {'project_id'=>:id},
      'hosting.project.health.status' => {'project_id'=>:id},
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
      when 'hosting.project.healthcheck', 'hosting.project.health.status'
        raise ArgumentError, 'Gatekeeper operator access required' unless Gatekeeper::Hosting::Access.super_admin?(actor)

        project = GatekeeperProject.find(values.fetch('project_id'))
        Gatekeeper::Hosting::Access.active!(project.gatekeeper_node) if intent == 'hosting.project.healthcheck'
        project
      else
        authorize_fleet!(actor)
        intent == 'hosting.fleet.rollout.list' ? GatekeeperRollout.all : GatekeeperRollout.find(values.fetch('rollout_id'))
      end
    rescue Gatekeeper::Hosting::Access::Denied => error
      raise ArgumentError, error.message
    end

    def server_scope(actor)
      Gatekeeper::Hosting::Access.nodes(actor)
    end

    def authorize_fleet!(actor)
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
    rescue Gatekeeper::Fleet::Rollouts::Invalid => error
      raise ArgumentError, error.message
    end

    def perform!(intent, target, values, actor:)
      case intent
      when 'hosting.server.list'
        SpecialistTasks.summary(target, %w[id name status updated_at])
      when 'hosting.server.status'
        target.attributes.slice('id', 'name', 'status', 'updated_at').merge(
          'links'=>[{'label'=>'Open server', 'url'=>"/dashboard/servers/#{target.id}"}])
      when 'hosting.project.healthcheck'
        job = Gatekeeper::HealthcheckProjectJob.perform_later(target.id,
          requested_by: "user:#{actor.id}", expected_node_id: target.gatekeeper_node_id, operator_id: actor.id)
        raise ArgumentError, 'Gatekeeper did not queue the health check' unless job

        {'project_id'=>target.id, 'job_id'=>job.job_id, 'status'=>'queued',
         'text'=>"Gatekeeper queued a health check for project ##{target.id}. Ask for the project’s health status to see the result."}
      when 'hosting.project.health.status'
        project_health_receipt(target)
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

    def project_health_receipt(project)
      operation = GatekeeperOperation.where(gatekeeper_project_id: project.id,
        gatekeeper_node_id: project.gatekeeper_node_id, capability: 'healthcheck_project')
        .order(id: :desc).first
      {'project_id'=>project.id, 'project_status'=>project.status, 'last_healthcheck_at'=>project.last_healthcheck_at&.iso8601,
       'latest_check'=>operation && operation.attributes.slice('id', 'status', 'started_at', 'completed_at', 'exit_status')
         .merge('job_id'=>operation.parameters.to_h['healthcheck_job_id']),
       'links'=>[{'label'=>'Open Gatekeeper project', 'url'=>"/gatekeeper/projects/#{project.id}"}]}
    end

    def rollout_receipt(rollout)
      rollout.attributes.slice('id', 'gatekeeper_release_id', 'status', 'scheduled_at').merge(
        'targets_by_status'=>rollout.gatekeeper_update_targets.group(:status).count,
        'links'=>[{'label'=>'Open rollout', 'url'=>"/dashboard/infrastructure/updates/#{rollout.id}"}])
    end
  end
end
