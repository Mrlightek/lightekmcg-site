module LightekMail
  class DiscoverySearch
    LIMIT = 100
    Match = Struct.new(:message, :timestamp, :retained, keyword_init: true)

    def initialize(account, query:, from:, through:)
      @account = account
      @query = query.to_s.strip.slice(0, 160)
      @from = date(from)
      @through = date(through)
      raise ArgumentError, "The end date must be on or after the start date." if @from && @through && @through < @from
    end

    def matches
      live = @account.messages.discoverable
      held = retained_scope
      results = fetch(live, Message.discovery_date, false) + fetch(held, RetainedMessage.arel_table[:sent_or_received_at], true)
      results.sort_by { |entry| [entry.timestamp, entry.message.id] }.reverse.first(LIMIT + 1)
    end

    private

    def retained_scope
      copies = RetainedMessage.where(account: @account)
      return copies if MatterHold.active.exists?(account: @account)

      rule = RetentionRule.find_by(account: @account)
      rule ? copies.where("sent_or_received_at > ?", rule.cutoff) : copies.none
    end

    def date(value)
      return if value.blank?
      raise ArgumentError, "Use YYYY-MM-DD dates." unless /\A\d{4}-\d{2}-\d{2}\z/.match?(value.to_s)

      Date.iso8601(value)
    rescue Date::Error
      raise ArgumentError, "Use valid YYYY-MM-DD dates."
    end

    def fetch(scope, field, retained)
      scope = scope.where(field.gteq(@from.in_time_zone)) if @from
      scope = scope.where(field.lt((@through + 1.day).in_time_zone)) if @through
      if @query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("LOWER(subject) LIKE ? OR LOWER(from_address) LIKE ? OR LOWER(text_body) LIKE ?", term, term, term)
      end
      scope.select(:id, :subject, :from_address, field.dup.as("mail_date")).order(field.desc, id: :desc).limit(LIMIT + 1).map do |message|
        timestamp = Time.find_zone!("UTC").parse(message.mail_date.to_s) unless message.mail_date.respond_to?(:iso8601)
        Match.new(message: message, timestamp: timestamp || message.mail_date, retained: retained)
      end
    end
  end
end
