class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "no-reply@lightekmcg.com")
  layout "mailer"
end
