require 'digest'
module LightekAccounting
  class Imports
    def self.preview!(access:,account:,raw:,mapping: nil)
      access.require!(:write)
      raise Access::Denied unless account.book.employer_id == access.employer.id
      table = StatementParser.table(raw)
      record = Import.new(book: account.book,bank_account: account,actor: access.actor,source_digest: Digest::SHA256.hexdigest(raw))
      selected = mapping.presence || table[:default_mapping]
      values = selected.present? ? StatementParser.rows(table,selected) : []
      record.data = {'raw'=>raw,'mapping'=>selected,'headers'=>table[:headers],'preview'=>values,'format'=>table[:format]}
      record.save!
      AuditEvent.record!(actor: access.actor,record: record,action: 'statement_previewed')
      record
    end
    def self.map!(access:,record:,mapping:)
      access.require!(:write)
      raise Access::Denied unless record.book.employer_id == access.employer.id
      record.with_lock do
        raise ArgumentError, 'A committed import cannot be remapped' unless record.status == 'preview'
        data = record.data
        rows = StatementParser.rows(StatementParser.table(data.fetch('raw')),mapping)
        record.update!(data: data.merge('mapping'=>mapping.to_h,'preview'=>rows))
      end
      record
    end
    def self.commit!(access:,record:,accept_possible_duplicates: false)
      access.require!(:write)
      raise Access::Denied unless record.book.employer_id == access.employer.id
      record.bank_account.with_lock do
        record.reload
        return record if record.status == 'committed'
        rows = record.data.fetch('preview')
        raise ArgumentError, 'Map and preview statement rows before committing' if rows.empty?
        previous = record.bank_account.transactions.to_a.map { |t| d=t.data; [t.posted_on.iso8601,d['amount_cents'],d['description']] }
        rows.each do |row|
          key = row['reference'].present? ? "bank:#{Digest::SHA256.hexdigest(row['reference'])}" : "file:#{record.source_digest}:#{row['row']}"
          existing = record.bank_account.transactions.find_by(source_key: key)
          if existing
            d = existing.data
            raise ArgumentError, 'Bank reference conflicts with an existing transaction' unless existing.posted_on.iso8601 == row['date'] && d['amount_cents'] == row['amount_cents']
            next
          end
          economic = [row['date'],row['amount_cents'],row['description']]
          raise ArgumentError, 'Possible duplicate rows need explicit review before import' if row['reference'].blank? && previous.include?(economic) && !accept_possible_duplicates
          category = Rules.category_for(record.book,row['description'])
          transaction = Transaction.new(book: record.book,bank_account: record.bank_account,statement_import: record,posted_on: row['date'],source_key: key,category: category)
          transaction.data = row.slice('description','amount_cents','reference')
          transaction.save!
          previous << economic
        end
        record.update!(status: 'committed')
        AuditEvent.record!(actor: access.actor,record: record,action: 'statement_committed')
      end
      record
    end
  end
end
