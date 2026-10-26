require "socket"
namespace :lightek_mail do
  desc "Stop all new Mail Studio submissions and queued SMTP sends"
  task :pause, [:reason] => :environment do |_task, args|
    LightekMail::SendingPolicy.synchronize { |policy| policy.update!(sending_enabled: false, stop_reason: args[:reason].presence || "Operator stop") }
    puts "LIGHTEK_MAIL_SENDING_PAUSED (SMTP already accepted by Postfix needs a separate queue hold)"
  end
  desc "Enable Mail Studio sending after live SMTP/DNS/scanning verification"
  task resume: :environment do
    LightekMail::SendingPolicy.synchronize { |policy| policy.update!(sending_enabled: true, stop_reason: nil) }
    puts "LIGHTEK_MAIL_SENDING_ENABLED"
  end
  desc "Clear an abuse suspension for an entire customer after operator review"
  task :resume_customer, [:user_id] => :environment do |_task, args|
    user = User.find(args[:user_id].presence || abort("Supply a reviewed customer user ID."))
    LightekMail::SendingPolicy.synchronize do
      LightekMail::CustomerSuspension.where(user_id: user.id).delete_all
      LightekMail::Account.where(user_id: user.id).update_all(suspended_at: nil, suspension_reason: nil, updated_at: Time.current)
    end
    puts "LIGHTEK_MAIL_CUSTOMER_SUSPENSION_CLEARED user_id=#{user.id} (rolling quotas and server stop remain in force)"
  end
  desc "Record trusted MTA/provider feedback; never feed unverified inbound DSNs here"
  task :feedback, [:message_id, :kind, :event_key] => :environment do |_task, args|
    LightekMail::Feedback.record!(message_id: args[:message_id], kind: args[:kind], event_key: args[:event_key])
    puts "LIGHTEK_MAIL_FEEDBACK_RECORDED"
  end
  desc "Grant Mail access to an existing user (run as the application operator)"
  task :grant_access, [:user_id] => :environment do |_task, args|
    user = User.find(args[:user_id].presence || abort("Supply an existing user ID."))
    user.grant_feature!("mail")
    puts "LIGHTEK_MAIL_ACCESS_GRANTED user_id=#{user.id}"
  end
  desc "Export verified enabled recipient routes for the SMTP administrator"
  task routes: :environment do
    addresses = LightekMail::Account.joins(:domain).where(enabled: true).where.not(lightek_mail_domains: {verified_at: nil}).order(:address).pluck(:address)
    puts "LIGHTEK_MAIL_ROUTES=#{JSON.generate(addresses)}"
  end
  desc "Check mail application and local SMTP availability; does not send a message"
  task doctor: :environment do
    puts "LIGHTEK_MAIL_ACCOUNTS=#{LightekMail::Account.count}"
    puts "LIGHTEK_MAIL_VERIFIED_DOMAINS=#{LightekMail::Domain.where.not(verified_at: nil).count}"
    puts "LIGHTEK_MAIL_INGRESS_CONFIGURED=#{ENV['LIGHTEK_MAIL_INGRESS_TOKEN'].to_s.bytesize >= 32}"
    puts "LIGHTEK_MAIL_SENDING_ENABLED=#{LightekMail::SendingPolicy.find_by(id: 1)&.sending_enabled? || false}"
    puts "LIGHTEK_MAIL_SUSPENDED_ACCOUNTS=#{LightekMail::Account.where.not(suspended_at: nil).count}"
    puts "LIGHTEK_MAIL_RECIPIENT_RESERVATIONS_24H=#{LightekMail::SendReservation.where('reserved_at > ?', 1.day.ago).sum(:recipient_count)}"
    settings = LightekMail::Transport.settings
    Socket.tcp(settings[:address], settings[:port], connect_timeout: 5) { |socket| puts "LIGHTEK_MAIL_SMTP_CONNECTED" }
    puts "This verifies a TCP connection only. Verify SMTP acceptance, DNS alignment, inbox delivery and inbound routing with operator-approved messages."
  end
  desc "Requeue undelivered queued records and mark stale in-flight SMTP submissions uncertain"
  task recover: :environment do
    LightekMail::Message.where(state: "submitting").where("updated_at < ?", 10.minutes.ago).update_all(state: "uncertain", error_message: "Worker stopped before SMTP acceptance was recorded. Check the mail queue before sending again.")
    LightekMail::Message.where(state: "queued").where("created_at < ?", 1.minute.ago).find_each { |message| LightekMail::DeliverJob.perform_later(message.id) }
    puts "LIGHTEK_MAIL_QUEUE_RECOVERY_COMPLETE"
  end
end
