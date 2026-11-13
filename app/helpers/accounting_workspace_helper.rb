module AccountingWorkspaceHelper
  def accounting_money(cents) = number_to_currency(BigDecimal(cents.to_s) / 100)
  def accounting_path(tab: nil, **values)
    dashboard_accounting_path({employer_id: @employer.id,book_id: @book&.id,tab: tab}.merge(values))
  end
  def accounting_cell_value(engine,sheet,address)
    value = engine.cell(sheet,address)
    value.is_a?(BigDecimal) ? value.to_s('F') : value
  rescue LightekAccounting::SheetFormula::Unsupported => error
    "Review: #{error.message}"
  end
end
