module LightekMail
  class Conversation
    LIMIT = 30

    def self.message_id(value)
      id = value.to_s.strip.delete_prefix("<").delete_suffix(">")
      id if id.bytesize.between?(1, 240) && id.match?(/\A[^\s<>]+\z/)
    end

    def self.parent(account, message)
      id = message_id(message.in_reply_to)
      account.messages.find_by(message_id: [id, "<#{id}>"]) if id
    end

    def self.ancestors(account, message)
      raise ActiveRecord::RecordNotFound unless message.account_id == account.id
      records, seen = [], [message.id]
      current = message
      (LIMIT - 1).times do
        current = parent(account, current)
        break unless current && !seen.include?(current.id)
        records.unshift(current)
        seen << current.id
      end
      records
    end

    def self.messages(account, message)
      records = (ancestors(account, message).reject(&:trashed?) + [message]).uniq(&:id)
      loop do
        ids = records.filter_map { |record| message_id(record.message_id) }
        break if ids.empty? || records.size >= LIMIT
        children = account.messages.visible.where(in_reply_to: ids + ids.map { |id| "<#{id}>" })
          .where.not(id: records.map(&:id)).order(:created_at, :id).limit(LIMIT - records.size).to_a
        break if children.empty?
        records.concat(children)
      end
      records.sort_by { |record| [record.created_at, record.id] }
    end

    def self.references(account, message)
      parent = parent(account, message)
      return [] unless parent
      (ancestors(account, parent) + [parent]).filter_map { |record| message_id(record.message_id) }.uniq.last(20)
    end
  end
end
