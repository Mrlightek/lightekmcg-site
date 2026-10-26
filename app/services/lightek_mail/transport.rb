module LightekMail
  class Transport
    def self.settings
      host = ENV.fetch("LIGHTEK_MAIL_SMTP_HOST", "127.0.0.1")
      local = %w[127.0.0.1 ::1 localhost].include?(host)
      result = {address: host, port: Integer(ENV.fetch("LIGHTEK_MAIL_SMTP_PORT", local ? "25" : "587")), domain: ENV.fetch("LIGHTEK_MAIL_HOST", "mail.lightekmcg.com"),
        open_timeout: 5, read_timeout: 20, enable_starttls_auto: !local, enable_starttls: !local, openssl_verify_mode: "peer"}
      if ENV["LIGHTEK_MAIL_SMTP_USERNAME"].present?
        result.merge!(user_name: ENV.fetch("LIGHTEK_MAIL_SMTP_USERNAME"), password: ENV.fetch("LIGHTEK_MAIL_SMTP_PASSWORD"), authentication: :plain)
      end
      result
    end
  end
end
