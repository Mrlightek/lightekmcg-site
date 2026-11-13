module LightekAccounting
  class Reports
    def self.profit_loss(book:,first:,last:)
      rows = book.transactions.includes(:category).where(posted_on: first..last)
      groups, months = {}, {}
      uncategorized = 0
      rows.find_each do |row|
        amount = row.amount_cents
        category = row.category
        unless category
          uncategorized += 1
          next
        end
        next if %w[transfer equity].include?(category.kind)
        group = (groups[category.id] ||= {'name'=>category.name,'kind'=>category.kind,'schedule_code'=>category.schedule_code,'actual_cents'=>0,'tax_cents'=>0,'deduction_bps'=>category.deduction_bps})
        signed = category.kind == 'expense' ? -amount : amount
        group['actual_cents'] += signed
        month = row.posted_on.strftime('%Y-%m')
        bucket = (months[month] ||= {'income_cents'=>0,'expense_cents'=>0})
        bucket[category.kind == 'income' ? 'income_cents' : 'expense_cents'] += signed
      end
      groups.each_value { |group| group['tax_cents'] = group['kind'] == 'expense' ? Rational(group['actual_cents'] * group['deduction_bps'],10000).round : group['actual_cents'] }
      income = groups.values.select { |v| v['kind'] == 'income' }.sum { |v| v['actual_cents'] }
      expenses = groups.values.select { |v| v['kind'] == 'expense' }.sum { |v| v['actual_cents'] }
      taxable = groups.values.sum { |v| v['kind'] == 'income' ? v['tax_cents'] : -v['tax_cents'] }
      {'groups'=>groups.values,'months'=>months,'income_cents'=>income,'expense_cents'=>expenses,'profit_cents'=>income-expenses,'tax_profit_cents'=>taxable,'uncategorized_count'=>uncategorized}
    end
  end
end
