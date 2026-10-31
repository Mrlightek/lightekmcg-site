module InfrastructureDashboardHelper
  def infrastructure_status_tone(status)
    case status.to_s
    when "healthy", "ready", "succeeded", "deployed", "active" then "good"
    when "failed", "delete_failed", "unreachable" then "danger"
    when "running", "queued", "provisioning", "deleting", "degraded" then "warning"
    else "neutral"
    end
  end

  def infrastructure_status_badge(status)
    tag.span(status.to_s.humanize, class: "infra-badge infra-#{infrastructure_status_tone(status)}")
  end
end
