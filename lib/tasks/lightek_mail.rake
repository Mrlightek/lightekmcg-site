require "socket"
namespace :lightek_mail do
  desc "Grant Mail access to an existing user (run as the application operator)"
  task :grant_access, [:user_id] => :environment do |_task, args|
    user = User.find(args.fetch(:user_id))
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
