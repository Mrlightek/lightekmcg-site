module LightekMail
  class Search
    # Operators are deliberately small and portable across PostgreSQL and SQLite.
    def self.apply(scope, query)
      query.to_s.slice(0, 240).scan(/(?:[^\s"]+|"[^"]*")+/).each do |token|
        key, value = token.split(":", 2)
        value = value.to_s.delete_prefix('"').delete_suffix('"')
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(value.downcase)}%"
        case key.downcase
        when "from", "subject"
          scope = scope.where("LOWER(#{key.downcase == 'from' ? 'from_address' : 'subject'}) LIKE ?", pattern)
        when "to"
          scope = scope.where("LOWER(CAST(to_addresses AS TEXT)) LIKE ?", pattern)
        when "is"
          scope = scope.where(read_at: nil, direction: "inbound") if value == "unread"
          scope = scope.where(starred: true) if value == "starred"
        when "has"
          scope = scope.where(id: ActiveStorage::Attachment.where(record_type: "LightekMail::Message", name: "attachments").select(:record_id)) if value == "attachment"
        when "after", "before"
          begin
            date = Date.iso8601(value).in_time_zone
            scope = scope.where("created_at #{key.downcase == 'after' ? '>=' : '<'} ?", date)
          rescue Date::Error
            raise ArgumentError, "Use YYYY-MM-DD for before: and after: searches."
          end
        else
          words = token.delete_prefix('"').delete_suffix('"')
          escaped = "%#{ActiveRecord::Base.sanitize_sql_like(words.downcase)}%"
          scope = scope.where("LOWER(subject) LIKE ? OR LOWER(from_address) LIKE ? OR LOWER(text_body) LIKE ?", *[escaped] * 3)
        end
      end
      scope
    end
  end
end
