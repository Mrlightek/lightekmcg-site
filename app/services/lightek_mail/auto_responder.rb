module LightekMail
  class AutoResponder
    def self.call(account, message, mail)
      return unless account.auto_reply_enabled? && account.auto_template && account.sending_ready?
      # RFC 3834 loop prevention; no replies to bounces, lists, bulk or automated mail.
      return if mail.from.to_a.size != 1 || mail.return_path.blank? || mail.return_path == "<>"
      return if mail["Auto-Submitted"].present? && mail["Auto-Submitted"].value.to_s.downcase != "no"
      return if %w[List-Id List-Unsubscribe X-Auto-Response-Suppress].any? { |key| mail[key].present? }
      return if mail["Precedence"]&.value.to_s.downcase.in?(%w[bulk list junk])
      return unless (Array(mail.to) + Array(mail.cc)).map(&:downcase).include?(account.address)
      return if mail["X-Spam-Flag"]&.value.to_s.upcase == "YES"
      sender = Submission.addresses(mail.from).first
      return unless mail.return_path.to_s.downcase == sender
      return if sender == account.address || Account.where(address: sender).exists? || sender.split("@").first.match?(/mailer-daemon|postmaster|no-?reply/i)
      reservation = nil
      account.with_lock do
        return if AutoReply.where(account: account, sender: sender).where("created_at > ?", 24.hours.ago).exists?
        reservation = AutoReply.create!(account: account, sender: sender, day: Date.current)
      end
      Submission.create!(account: account, attributes: {to: sender, template_id: account.auto_template_id, variables: {name: mail[:from]&.display_names&.first.presence || sender, email: sender, company: account.display_name, subject: message.subject}, in_reply_to: "<#{message.message_id}>"}, idempotency_key: "auto_reply_#{message.id}")
    rescue ArgumentError, Submission::Unavailable, ActiveRecord::RecordNotUnique => error
      Rails.logger.info("[LightekMail] automatic reply skipped account_id=#{account.id} reason_class=#{error.class.name}")
    end
  end
end
