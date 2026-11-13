module LightekAccounting
  class WorkbookConversion
    def self.apply!(access:,workbook:,sheet:,header_row:,target:)
      access.require!(:write)
      raise Access::Denied unless workbook.book.employer_id == access.employer.id
      workbook.book.with_lock do
        schema = workbook.data
        table = WorkbookSchema.table(schema,sheet,header_row: header_row)
        headers = table[:headers].map { |h| h.downcase.strip }
        column = ->(name) { headers.index(name) || (raise ArgumentError,"Conversion needs a #{name} column") }
        signature = Digest::SHA256.hexdigest(JSON.generate([schema['sheets'],sheet,header_row,target]))
        prior = Array(schema['conversions']).find { |conversion| conversion['signature'] == signature }
        return prior if prior
        ids = []
        case target
        when 'categories'
          name_col,kind_col = column.call('name'),column.call('kind')
          table[:rows].each do |row|
            name,kind = row[name_col].to_s.strip,row[kind_col].to_s.strip.downcase
            raise ArgumentError,'Category name is required' if name.blank?
            record = workbook.book.categories.find_by('LOWER(name) = ?',name.downcase)
            if record
              raise ArgumentError,'Existing category has a different type; review before converting' unless record.kind == kind
            else
              percent_index = headers.index('deductible percent')
              percent = percent_index ? BigDecimal(row[percent_index]) : BigDecimal('100')
              raise ArgumentError,'Deductible percent must be between 0 and 100' unless percent.finite? && percent >= 0 && percent <= 100 && (percent * 100).frac.zero?
              schedule_index = headers.index('schedule c')
              record = workbook.book.categories.create!(name: name,kind: kind,deduction_bps: (percent * 100).to_i,schedule_code: schedule_index ? row[schedule_index].to_s : nil)
              AuditEvent.record!(actor: access.actor,record: record,action: 'workbook_category_converted')
            end
            ids << record.id
          end
        when 'keyword_rules'
          keyword_col,category_col = column.call('keyword'),column.call('category')
          table[:rows].each do |row|
            keyword = row[keyword_col].to_s.strip
            raise ArgumentError,'Rule keyword must be between 1 and 200 characters' unless keyword.length.between?(1,200)
            category = workbook.book.categories.find_by!('LOWER(name) = ?',row[category_col].to_s.strip.downcase)
            existing = Rule.where(book: workbook.book).detect { |rule| rule.data['keyword'].casecmp?(keyword) }
            if existing
              raise ArgumentError,'Existing keyword maps to a different category' unless existing.category_id == category.id
              ids << existing.id
              next
            end
            priority_index = headers.index('priority')
            raw_priority = priority_index ? BigDecimal(row[priority_index].to_s) : BigDecimal('100')
            raise ArgumentError,'Priority must be a whole number' unless raw_priority.finite? && raw_priority.frac.zero?
            priority = raw_priority.to_i
            raise ArgumentError,'Priority must be between 0 and 10000' unless (0..10000).cover?(priority)
            record = Rule.new(book: workbook.book,category: category,priority: priority)
            record.data = {'keyword'=>keyword}
            record.save!
            AuditEvent.record!(actor: access.actor,record: record,action: 'workbook_rule_converted')
            ids << record.id
          end
        else
          raise ArgumentError,'Choose categories or keyword rules for this conversion'
        end
        result = {'signature'=>signature,'target'=>target,'record_ids'=>ids,'converted_at'=>Time.current.iso8601}
        workbook.update!(data: schema.merge('conversions'=>Array(schema['conversions']) + [result]))
        AuditEvent.record!(actor: access.actor,record: workbook,action: 'workbook_schema_applied')
        result
      end
    end
  end
end
