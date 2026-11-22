module LightekAccounting
  class Rules
    def self.category_for(book, description, rules: saved_rules(book))
      normalized = description.to_s.downcase
      rules.find { |keyword, _| normalized.include?(keyword) }&.last
    end

    def self.saved_rules(book)
      Rule.where(book: book).includes(:category).order(:priority, :id).filter_map do |rule|
        keyword = rule.data.fetch('keyword').downcase
        [keyword, rule.category] if keyword.present? && rule.category&.book_id == book.id
      end
    end
    private_class_method :saved_rules
    def self.apply_saved!(access:, book:)
      access.require!(:write)
      raise Access::Denied unless book.employer_id == access.employer.id

      categorized = 0
      pending = book.transactions.where(category_id: nil, reconciliation_id: nil)
      book.with_lock do
        rules = saved_rules(book)

        if rules.any?
          pending.lock.find_each do |row|
            category = category_for(book, row.data['description'], rules: rules)
            next unless category

            row.update!(category: category)
            AuditEvent.record!(actor: access.actor, record: row, action: 'transaction_categorized_by_rule')
            categorized += 1
          end
        end
        {'categorized_count' => categorized, 'uncategorized_count' => pending.count}
      end
    end
    def self.categorize!(access:,book:,ids:,category:)
      access.require!(:write)
      raise Access::Denied unless book.employer_id == access.employer.id && category.book_id == book.id
      book.with_lock do
        wanted = Array(ids).map { |id| Integer(id.to_s,10) }.uniq
        raise ArgumentError, 'Select between 1 and 500 rows' unless wanted.length.between?(1,500)
        rows = book.transactions.where(id: wanted).to_a
        raise Access::Denied unless rows.length == wanted.length
        rows.each do |row|
          row.update!(category: category)
          AuditEvent.record!(actor: access.actor,record: row,action: 'transaction_categorized')
        end
      end
    end
  end
end
