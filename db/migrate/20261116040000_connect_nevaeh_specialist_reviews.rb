# One-time scope upgrade; normal directory reads must never regrant a removed permission.
class ConnectNevaehSpecialistReviews < ActiveRecord::Migration[8.0]
  class Agent < ActiveRecord::Base
    self.table_name='nevaeh_os_agents'
  end
  LEGACY={
    'website'=>%w[site.* website.* cms.*],
    'sales'=>%w[sales.* crm.* growth.*],
    'finance'=>%w[accounting.* bank.* dymond.bank.* susu.*],
    'payroll'=>%w[payroll.* hr.*],
    'commerce'=>%w[commerce.* ecommerce.* shipping.* catalog.* orders.*],
    'people'=>%w[directory.* people.* hr.*],
    'hosting'=>%w[hosting.* server.* deployment.* dns.* domains.*],
    'compliance'=>%w[compliance.* legal.*]
  }.freeze
  def up
    Agent.where(system_key:LEGACY.keys,deleted_at:nil).find_each do |agent|
      agent.with_lock do
        previous=LEGACY.fetch(agent.system_key)
        agent.update!(allowed_capabilities:previous+["operations.#{agent.system_key}.review"]) if agent.allowed_capabilities==previous
      end
    end
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Keep explicitly reviewed specialist permissions; remove them through role management if required.'
  end
end
