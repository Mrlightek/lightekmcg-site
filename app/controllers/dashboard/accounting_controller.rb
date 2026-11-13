require 'csv'
class Dashboard::AccountingController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  helper AccountingWorkspaceHelper
  protect_from_forgery with: :exception
  before_action :context!
  rescue_from LightekAccounting::Access::Denied, LightekPeople::Access::Denied, with: ->(_) { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: ->(_) { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: :invalid!
  def index
    load_workspace
  end
  def book
    @access.require!(:admin)
    @book = LightekAccounting::Book.create!(params.require(:book).permit(:name,:timezone).merge(employer: @employer))
    LightekAccounting::AuditEvent.record!(actor: current_user,record: @book,action: 'book_created')
    back!('Book created')
  end
  def account
    write! do
      account = @book.bank_accounts.new(params.require(:account).permit(:name,:opening_on))
      account.data = {'opening_cents'=>LightekAccounting::Money.cents!(params[:account][:opening_amount]), 'last_four'=>params[:account][:last_four].to_s.last(4)}
      account.save!
      audit!('bank_account_created',account)
    end
    back!('Bookkeeping account created; this does not connect or move bank funds',tab: 'accounts')
  end
  def category
    write! do
      values = params.require(:category).permit(:name,:kind,:schedule_code)
      percent = BigDecimal(params[:category][:deduction_percent].to_s)
      raise ArgumentError, 'Deductible percentage must be from 0 to 100 with at most two decimals' unless percent.finite? && percent >= 0 && percent <= 100 && (percent * 100).frac.zero?
      record = @book.categories.create!(values.merge(deduction_bps: (percent * 100).to_i))
      audit!('category_created',record)
    end
    back!('Category saved',tab: 'rules')
  end
  def transaction
    write! do
      account = @book.bank_accounts.find(params.require(:entry)[:bank_account_id])
      account.with_lock do
        record = @book.transactions.new(bank_account: account,posted_on: params[:entry][:posted_on],source_key: "manual:#{SecureRandom.uuid}")
        record.category = @book.categories.find(params[:entry][:category_id]) if params[:entry][:category_id].present?
        record.data = {'amount_cents'=>LightekAccounting::Money.cents!(params[:entry][:amount]), 'description'=>params[:entry][:description].to_s.first(2000)}
        record.save!
        audit!('manual_transaction_recorded',record)
      end
    end
    back!('Transaction recorded')
  end
  def categorize
    require_book!
    LightekAccounting::Rules.categorize!(access: @access,book: @book,ids: params[:transaction_ids],category: @book.categories.find(params[:category_id]))
    back!('Selected transactions categorized')
  end
  def rule
    write! do
      record = LightekAccounting::Rule.new(book: @book,category: @book.categories.find(params[:rule][:category_id]),priority: params[:rule][:priority])
      keyword = params[:rule][:keyword].to_s.strip
      raise ArgumentError, 'Enter a keyword from 1 to 200 characters' unless keyword.length.between?(1,200)
      record.data = {'keyword'=>keyword}
      record.save!
      audit!('categorization_rule_created',record)
    end
    back!('Keyword rule saved; lower priority numbers match first',tab: 'rules')
  end
  def import
    require_book!
    @access.require!(:write)
    raw = params[:file].respond_to?(:read) ? params[:file].read(LightekAccounting::StatementParser::MAX_BYTES + 1) : params[:pasted_statement].to_s
    record = LightekAccounting::Imports.preview!(access: @access,account: @book.bank_accounts.find(params[:bank_account_id]),raw: raw)
    back!('Statement uploaded securely; map and review before committing',tab: 'imports',import_id: record.id)
  end
  def map
    require_book!
    record = LightekAccounting::Import.where(book: @book).find(params[:id])
    LightekAccounting::Imports.map!(access: @access,record: record,mapping: params.require(:mapping).permit(:date,:description,:memo,:amount,:reference,:credit,:debit,:mode,:date_format).to_h)
    back!('Statement preview updated',tab: 'imports',import_id: record.id)
  end
  def commit
    require_book!
    @access.require!(:write)
    record = LightekAccounting::Import.where(book: @book).find(params[:id])
    record.with_lock do
      unless %w[committed queued].include?(record.status)
        record.update!(status: 'queued')
        AccountingImportJob.perform_later(record.id,current_user.id,params[:accept_duplicates] == '1')
      end
    end
    back!('Import queued; current permissions will be checked again by the worker',tab: 'imports',import_id: record.id)
  end
  def reconcile
    require_book!
    account = @book.bank_accounts.find(params[:bank_account_id])
    values = {account: account,first: Date.iso8601(params[:starts_on]),last: Date.iso8601(params[:ends_on]),
      starting: LightekAccounting::Money.cents!(params[:starting_amount]),ending: LightekAccounting::Money.cents!(params[:ending_amount]),selected: Array(params[:selected]).map { |id| Integer(id,10) }.uniq}
    if params[:finalize] == '1'
      LightekAccounting::Reconcile.finalize!(access: @access,**values)
      back!('Reconciliation proved and finalized',tab: 'reconcile',account_id: account.id)
    else
      @proof = LightekAccounting::Reconcile.proof(**values)
      return render(json: @proof) if request.format.json?
      load_workspace(tab: 'reconcile')
      render :index
    end
  end
  def reopen
    require_book!
    LightekAccounting::Reconcile.reopen!(access: @access,record: LightekAccounting::Reconciliation.where(book: @book).find(params[:id]))
    back!('Latest reconciliation reopened; its prior proof remains in history',tab: 'reconcile')
  end
  def export
    require_book!
    data = CSV.generate do |out|
      out << %w[date account description amount_cents category schedule_code reconciliation_id]
      @book.transactions.includes(:bank_account,:category).order(:posted_on,:id).find_each do |row|
        out << [row.posted_on,row.bank_account.name,row.data['description'],row.amount_cents,row.category&.name,row.category&.schedule_code,row.reconciliation_id].map { |v| v.is_a?(String) && v.match?(/\A[ \t\r\n\f\v\uFEFF]*[=+@\-]|\A[\t\r\n]/) ? "'#{v}" : v }
      end
    end
    audit!('ledger_exported',@book)
    send_data data,type: 'text/csv',filename: "book-#{@book.id}-ledger-cents.csv",disposition: :attachment
  end
  def tax
    require_book!
    raise ArgumentError, 'Confirm the estimate scope and reviewed inputs' unless params[:tax_reviewed] == '1'
    inputs = tax_inputs
    @estimate = LightekAccounting::TaxEstimate.calculate(inputs)
    load_workspace(tab: 'reports')
    render :index
  end
  def workbook
    write! do
      file = params.require(:file)
      schema = LightekAccounting::WorkbookSchema.parse(file.read(5_000_001),filename: file.original_filename)
      record = LightekAccounting::Workbook.new(book: @book,actor: current_user,name: file.original_filename.to_s.first(150))
      record.data = schema
      record.save!
      audit!('workbook_schema_imported',record)
      @new_workbook = record
    end
    back!('Workbook converted to a private native workspace; review calculated and unsupported cells',tab: 'workbooks',workbook_id: @new_workbook.id)
  end
  def cell
    write! do
      record = LightekAccounting::Workbook.where(book: @book).find(params[:id])
      record.with_lock do
        schema = record.data
        sheet = schema['sheets'].find { |s| s['name'] == params[:sheet] } || (raise ArgumentError, 'Unknown worksheet')
        target = sheet['cells'].fetch(params[:address])
        raise ArgumentError, 'Calculated cells cannot be overwritten; edit their inputs' if target['formula']
        target['value'] = case target['type']
        when 'number' then BigDecimal(params[:value].to_s).to_s('F')
        when 'date' then Date.iso8601(params[:value]).iso8601
        when 'boolean' then params[:value] == 'true'
        else params[:value].to_s.first(2000)
        end
        record.update!(data: schema)
        audit!('native_workbook_input_changed',record)
      end
    end
    back!('Input saved; dependent formulas recalculate from native data',tab: 'workbooks',workbook_id: params[:id])
  end
  def convert
    require_book!
    record = LightekAccounting::Workbook.where(book: @book).find(params[:id])
    header_row = Integer(params[:header_row].presence || '1',10)
    if %w[categories keyword_rules].include?(params[:target])
      LightekAccounting::WorkbookConversion.apply!(access: @access,workbook: record,sheet: params[:sheet],header_row: header_row,target: params[:target])
      return back!('Spreadsheet structure converted into native categories or keyword rules',tab: 'rules')
    end
    write! do
      table = LightekAccounting::WorkbookSchema.table(record.data,params[:sheet],header_row: header_row)
      raise ArgumentError, 'Header row must be within the sheet' if table[:headers].empty?
      raw = CSV.generate { |csv| csv << table[:headers];table[:rows].each { |row| csv << row } }
      imported = LightekAccounting::Imports.preview!(access: @access,account: @book.bank_accounts.find(params[:bank_account_id]),raw: raw)
      audit!('workbook_converted_to_statement',record)
      @new_import = imported
    end
    back!('Worksheet converted to native transaction import; map, preview and commit it',tab: 'imports',import_id: @new_import.id)
  end
  def automation
    require_book!
    @access.require!(:admin)
    action = params[:action_kind]
    raise ArgumentError, 'Choose report refresh or reviewed tax reserve refresh' unless %w[reports tax_reserve].include?(action)
    cadence = params[:cadence]
    raise ArgumentError, 'Choose a daily or weekly cadence' unless %w[daily weekly].include?(cadence)
    values = {'action'=>action,'cadence'=>cadence}
    if action == 'tax_reserve'
      raise ArgumentError, 'Confirm the reviewed estimate inputs' unless params[:tax_reviewed] == '1'
      values['tax_inputs'] = tax_inputs
      LightekAccounting::TaxEstimate.calculate(values['tax_inputs'])
    end
    record = LightekAccounting::Automation.new(book: @book,actor: current_user,next_run_at: Time.current)
    record.data = values
    record.save!
    AccountingRefreshJob.perform_later(record.id)
    audit!('accounting_worker_scheduled',record)
    back!('Worker scheduled; each execution rechecks current employer permissions',tab: 'reports')
  end
  def stop_automation
    write!(:admin) do
      record = LightekAccounting::Automation.where(book: @book).find(params[:id])
      record.update!(enabled: false)
      audit!('accounting_worker_stopped',record)
    end
    back!('Worker stopped',tab: 'reports')
  end
  private
  def context!
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    return head(:forbidden) if Current.session&.connect_delegation.present?
    return redirect_to(identity_security_path,alert: 'Enable an authenticator to access confidential accounting records.') unless LightekIdentity::Mfa.enabled?(current_user)
    return head(:forbidden) unless LightekIdentity::Mfa.fresh?(Current.session)
    @employers = LightekPeople::Access.employers_for(current_user)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.first!
    @access = LightekAccounting::Access.new(actor: current_user,employer: @employer).require!
    # Existing business workspace eligibility and billing remain authoritative.
    raise LightekAccounting::Access::Denied unless @employer.can_access_feature?('commerce_workspace') || @employer.can_access_feature?('bookkeeping_workspace')
    @can_write, @can_review, @can_admin = @access.allowed?(:write), @access.allowed?(:review), @access.allowed?(:admin)
    @books = @access.books.order(:name)
    @book = params[:book_id].present? ? @books.find(params[:book_id]) : @books.first
  end
  def load_workspace(tab: nil)
    @tab = tab || params[:tab].presence || 'ledger'
    return unless @book
    @accounts = @book.bank_accounts.order(:name)
    @categories = @book.categories.order(:kind,:name)
    @year = Integer(params[:year].presence || Date.current.year)
    raise ArgumentError, 'Choose a reporting year from 2000 through 2100' unless (2000..2100).cover?(@year)
    @month = Integer(params[:month],10) if params[:month].present?
    raise ArgumentError, 'Choose a month from 1 to 12' if @month && !(1..12).cover?(@month)
    report_first = Date.new(@year,@month || 1,1)
    report_last = @month ? report_first.end_of_month : Date.new(@year,12,31)
    @report = LightekAccounting::Reports.profit_loss(book: @book,first: report_first,last: report_last) if @tab == 'reports'
    scope = @book.transactions.includes(:category,:bank_account).order(posted_on: :desc,id: :desc)
    scope = scope.where(bank_account_id: @accounts.find(params[:account_id]).id) if params[:account_id].present?
    scope = scope.where(category_id: @categories.find(params[:category_id]).id) if params[:category_id].present?
    scope = scope.where(posted_on: Date.iso8601(params[:first])..Date.iso8601(params[:last])) if params[:first].present? && params[:last].present?
    @transactions = []
    if params[:q].present?
      # Descriptions stay encrypted: scan bounded pages before limiting matches.
      query,offset = params[:q].to_s.downcase,0
      loop do
        page = scope.offset(offset).limit(500).to_a
        @transactions.concat(page.select { |row| row.data['description'].to_s.downcase.include?(query) })
        break if page.size < 500 || @transactions.size >= 500
        offset += 500
      end
      @transactions = @transactions.first(500)
    else
      @transactions = scope.limit(500).to_a
    end
    @imports = LightekAccounting::Import.where(book: @book).order(id: :desc).limit(20)
    @import = @imports.find_by(id: params[:import_id]) || @imports.first
    @rules = LightekAccounting::Rule.where(book: @book).includes(:category).order(:priority,:id)
    @reconciliations = LightekAccounting::Reconciliation.where(book: @book).includes(:bank_account).order(ends_on: :desc).limit(30)
    @reconcile_account = params[:account_id].present? ? @accounts.find(params[:account_id]) : @accounts.first
    if @reconcile_account
      @uncleared = @reconcile_account.transactions.where(reconciliation_id: nil).order(:posted_on,:id).limit(1000)
      @prior_reconciliation = @reconcile_account.reconciliations.where(status: 'final').order(ends_on: :desc).first
    end
    @workbooks = LightekAccounting::Workbook.where(book: @book).order(id: :desc).limit(20)
    @workbook = @workbooks.find_by(id: params[:workbook_id]) || @workbooks.first
    @automations = LightekAccounting::Automation.where(book: @book).order(id: :desc).limit(20)
    @audit_events = LightekAccounting::AuditEvent.where(book: @book).includes(:actor).order(id: :desc).limit(50)
  end
  def require_book! = (@book || (raise ArgumentError, 'Create or choose a book first'))
  def write!(permission = :write)
    require_book!
    @access.require!(permission)
    @book.with_lock { yield }
  end
  def tax_inputs
    source = params.require(:tax)
    values = {'year'=>Integer(source[:year].to_s,10),'filing_status'=>source[:filing_status], 'prior_full_year'=>source[:prior_full_year] == '1'}
    %w[profit other_ordinary_income social_security_wages medicare_wages spouse_medicare_wages agi_adjustments deductions nonrefundable_credits refundable_credits other_taxes withholding prior_tax prior_agi].each do |field|
      values["#{field}_cents"] = LightekAccounting::Money.cents!(source[field]) if source[field].present?
    end
    if source[:payments]
      entries = source[:payments].to_unsafe_h.values
      raise ArgumentError, 'At most 20 payment records are supported in this worksheet' if entries.length > 20
      values['payments'] = entries.reject { |row| row['date'].blank? && row['amount'].blank? }.map { |row| {'date'=>Date.iso8601(row.fetch('date')).iso8601,'amount_cents'=>LightekAccounting::Money.cents!(row.fetch('amount'))} }
    end
    values['profit_cents'] ||= LightekAccounting::Reports.profit_loss(book: @book,first: Date.new(values['year'],1,1),last: Date.new(values['year'],12,31)).fetch('tax_profit_cents')
    values
  end
  def back!(notice,tab: 'ledger',**values)
    redirect_to dashboard_accounting_path({employer_id: @employer.id,book_id: @book&.id,tab: tab}.merge(values)),notice: notice,status: :see_other
  end
  def audit!(action,record) = LightekAccounting::AuditEvent.record!(actor: current_user,record: record,action: action)
  def invalid!(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
    return render(json: {error: message},status: :unprocessable_entity) if request.format.json?
    fallback = case action_name
    when 'import','map','commit' then 'imports'
    when 'tax','automation','stop_automation' then 'reports'
    when 'reconcile','reopen' then 'reconcile'
    when 'workbook','cell','convert' then 'workbooks'
    when 'category','rule' then 'rules'
    when 'account' then 'accounts'
    else 'ledger'
    end
    redirect_to dashboard_accounting_path(employer_id: @employer&.id,book_id: @book&.id,tab: params[:tab].presence || fallback),alert: message,status: :see_other
  end
end
