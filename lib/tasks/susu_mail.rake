namespace :susu do
  task mail_readiness: :environment do
    puts "=== SUSU MAIL READINESS ==="
    puts "SMTP address:    #{ENV["SMTP_ADDRESS"].present? ? "PRESENT" : "MISSING"}"
    puts "SMTP username:   #{ENV["SMTP_USERNAME"].present? ? "PRESENT" : "MISSING"}"
    puts "SMTP password:   #{ENV["SMTP_PASSWORD"].present? ? "PRESENT" : "MISSING"}"
    puts "Mail from:       #{ENV.fetch("MAIL_FROM", "Susu by Lightek <susu@lightekmcg.com>")}"
    puts "Delivery method: #{ActionMailer::Base.delivery_method}"
    puts "Pending invites: #{SusuInvitation.pending.count}"
  end
end
