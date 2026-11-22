# frozen_string_literal: true

module LightekAccounting
  module FilingWorkpaper
    module_function

    def build(book:, year:, today: Date.current)
      first = Date.new(year, 1, 1)
      last = Date.new(year, 12, 31)
      report = Reports.profit_loss(book: book, first: first, last: last)
      accounts = book.bank_accounts.where("opening_on <= ?", last)
      blockers = []
      blockers << "The tax year is still open" if last >= today
      blockers << "Categorize the remaining transactions" if report.fetch("uncategorized_count").positive?
      blockers << "Review the Schedule C mappings" if report.fetch("groups").any? { |group| group.fetch("schedule_code").blank? }
      blockers << "Set up a bank account for this book" unless accounts.exists?
      accounts.find_each do |account|
        unless account.reconciliations.where(status: "final").where("starts_on <= ? AND ends_on >= ?", last, last).exists?
          blockers << "Reconcile bank account ##{account.id} through the tax year end"
        end
      end
      {
        "kind" => "schedule_c_workpaper", "tax_year" => year, "book_id" => book.id,
        "status" => blockers.empty? ? "ready_for_preparer" : "needs_attention",
        "filing_status" => "provider_required", "blockers" => blockers, "report" => report
      }
    end
  end
end
