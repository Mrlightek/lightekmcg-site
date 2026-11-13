module LightekMail
  class SpamFilter
    def self.classify(account:, sender:, scan:)
      return {junk: true, spam_score: nil, spam_reason: "Scanner unavailable; held for review", spam_scanned_at: nil} unless scan
      sender = sender.to_s.downcase
      matches = ->(entries) { Array(entries).include?(sender) || Array(entries).include?(sender.split("@").last) }
      action, score = scan.fetch("action"), scan.fetch("score")
      reason = if matches.call(account.blocked_senders)
        "Blocked sender"
      elsif action.in?(["reject", "discard", "quarantine", "greylist", "soft reject"])
        "Server spam verdict: #{action}"
      elsif matches.call(account.allowed_senders) && score < 6
        nil
      elsif score >= (account.spam_filter_level == "strict" ? 4 : 6) || action != "no action"
        "Spam score or server verdict exceeded this mailbox’s filter"
      end
      {junk: reason.present?, spam_score: score, spam_reason: reason, spam_scanned_at: Time.current}
    end
  end
end
