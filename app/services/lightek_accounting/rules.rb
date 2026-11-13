module LightekAccounting
  class Rules
    def self.category_for(book,description)
      normalized = description.to_s.downcase
      rule = Rule.where(book: book).includes(:category).order(:priority,:id).detect { |r| normalized.include?(r.data.fetch('keyword').downcase) }
      rule&.category if rule&.category&.book_id == book.id
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
