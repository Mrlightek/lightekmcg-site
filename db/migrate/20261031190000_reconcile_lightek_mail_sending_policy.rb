class ReconcileLightekMailSendingPolicy < ActiveRecord::Migration[8.0]
  def up
    policy_class = Class.new(ActiveRecord::Base) { self.table_name = "lightek_mail_sending_policies" }
    policy = policy_class.create_or_find_by!(id: 1)
    policy.with_lock do
      # A recorded administrator/abuse stop always wins. An already enabled
      # canonical policy is also authoritative and needs no conversion.
      next if policy.sending_enabled? || policy.stop_reason.present?
      legacy = connection.select_one("SELECT active FROM sending_policies ORDER BY id LIMIT 1") if table_exists?(:sending_policies)
      if legacy
        enabled = ActiveModel::Type::Boolean.new.cast(legacy.fetch("active")) == true
        policy.update!(sending_enabled: enabled, stop_reason: enabled ? nil : "Preserved legacy mail sending pause")
      elsif table_exists?(:lightek_mail_messages) && connection.select_value("SELECT 1 FROM lightek_mail_messages WHERE direction = 'outbound' AND state = 'sent' LIMIT 1")
        # The old model defaulted to enabled when its legacy table had no row.
        # Carry that behavior forward only for an installation that actually sent
        # mail; fresh installations retain their paused default.
        policy.update!(sending_enabled: true)
      end
    end
  end

  def down
    # Retain operational settings on rollback; reversing a schema migration must
    # not enable or pause live mail.
  end
end
