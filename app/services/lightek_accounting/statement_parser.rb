require 'csv'
require 'date'
require 'cgi'
module LightekAccounting
  class StatementParser
    MAX_BYTES = 5_000_000
    MAX_ROWS = 25_000
    def self.table(raw)
      raise ArgumentError, 'Statement exceeds 5 MB' if raw.bytesize > MAX_BYTES
      text = raw.dup.force_encoding('UTF-8').delete_prefix("\uFEFF")
      raise ArgumentError, 'Upload a UTF-8 statement' unless text.valid_encoding?
      if text.match?(/<OFX[>\s]/i) || text.start_with?('OFXHEADER:')
        raise ArgumentError, 'XML document types and entities are not supported' if text.match?(/<!DOCTYPE|<!ENTITY/i)
        entries = text.scan(/<STMTTRN>(.*?)<\/STMTTRN>/im).flatten
        raise ArgumentError, 'No OFX/QFX transactions found' if entries.empty?
        rows = entries.map do |entry|
          %w[DTPOSTED NAME MEMO TRNAMT FITID].map { |tag| CGI.unescapeHTML(entry[/<#{tag}[^>]*>([^<]*)/im,1].to_s.strip) }
        end
        raise ArgumentError, 'Too many transactions' if rows.length > MAX_ROWS
        {headers: %w[date description memo amount reference], rows: rows, format: 'ofx', default_mapping: {'date'=>'0','description'=>'1','memo'=>'2','amount'=>'3','reference'=>'4','date_format'=>'ofx','mode'=>'signed'}}
      else
        first = text.lines.first.to_s
        delimiter = first.count("\t") > first.count(',') ? "\t" : ','
        rows = CSV.parse(text,col_sep: delimiter,field_size_limit: 50_000)
        headers = rows.shift
        raise ArgumentError, 'Statement needs headers and data rows' unless headers && headers.any? && rows.any?
        raise ArgumentError, 'Too many statement rows or columns' if rows.length > MAX_ROWS || headers.length > 100
        raise ArgumentError, 'Statement rows have inconsistent column counts' unless rows.all? { |r| r.length == headers.length }
        {headers: headers.map { |h| h.to_s.strip }, rows: rows, format: 'delimited', default_mapping: {}}
      end
    rescue CSV::MalformedCSVError
      raise ArgumentError, 'Statement is not valid CSV or TSV'
    end
    def self.rows(table,mapping)
      mapping = mapping.stringify_keys
      column = ->(row,key) do
        index = mapping[key].to_s
        next '' if index.blank?
        raise ArgumentError, 'Select a valid column' unless index.match?(/\A\d+\z/) && index.to_i < table[:headers].size
        row[index.to_i].to_s.strip
      end
      table[:rows].each_with_index.map do |row,index|
        raw_date = column.call(row,'date')
        date = case mapping['date_format']
        when 'iso' then Date.iso8601(raw_date)
        when 'mdy'
          raise ArgumentError, 'Use month/day/four-digit-year' unless raw_date.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/)
          Date.strptime(raw_date,'%m/%d/%Y')
        when 'dmy'
          raise ArgumentError, 'Use day/month/four-digit-year' unless raw_date.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/)
          Date.strptime(raw_date,'%d/%m/%Y')
        when 'ofx' then Date.strptime(raw_date[0,8],'%Y%m%d')
        else raise ArgumentError, 'Choose an explicit date format'
        end
        amount = if mapping['mode'] == 'split'
          credit, debit = column.call(row,'credit'), column.call(row,'debit')
          raise ArgumentError, 'A row cannot have both deposit and withdrawal amounts' if credit.present? && debit.present? && Money.cents!(credit) != 0 && Money.cents!(debit) != 0
          c, d = credit.blank? ? 0 : Money.cents!(credit), debit.blank? ? 0 : Money.cents!(debit)
          raise ArgumentError, 'Split deposits and withdrawals must be positive' if c.negative? || d.negative?
          c - d
        else
          value = Money.cents!(column.call(row,'amount'))
          mapping['mode'] == 'debits_positive' ? -value : value
        end
        {'date'=>date.iso8601,'description'=>[column.call(row,'description'),column.call(row,'memo')].reject(&:blank?).join(' · ').first(2000),
          'amount_cents'=>amount,'reference'=>column.call(row,'reference').first(255),'row'=>index + 1}
      rescue ArgumentError => error
        raise ArgumentError, "Row #{index + 1}: #{error.message}"
      end
    end
  end
end
