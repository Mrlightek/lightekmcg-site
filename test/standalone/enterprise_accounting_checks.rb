require_relative 'people_payroll_checks'
require 'minitest/mock'
require 'base64'
require 'openssl'
# Connect and enterprise identity share the real session/MFA tables in this harness.
ActiveRecord::Schema.define do
  add_column :users, :agency_id, :bigint
  add_column :users, :upstream_share_bps, :integer, default: 0
  create_table(:dymond_site_sites) do |t|
    t.string :name; t.string :host; t.references :tenant, polymorphic: true; t.json :manifest, default: {}
  end
end
%w[20261112190000_create_lightek_connect 20261113230000_add_connect_mfa_handoff].each do |file|
  source = ROOT.join("db/migrate/#{file}.rb").read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
  source = source.lines.reject { |line| line.include?('add_column :sessions, :connect_delegation') }.join
  eval(source, TOPLEVEL_BINDING)
end
CreateLightekConnect.new.migrate(:up)
AddConnectMfaHandoff.new.migrate(:up)

module LightekVault
  class MasterKey
    class ConfigurationError < StandardError; end
    def self.resolve!(**) = Base64.strict_encode64('test-only-identity-key-32-bytes!!!'.ljust(32,'!')[0,32])
  end
end
require ROOT.join('app/services/lightek_vault/crypto')
require ROOT.join('app/services/lightek_identity/sealed')
require ROOT.join('app/services/lightek_identity/mfa')
class ApplicationJob
  class << self
    attr_accessor :enqueued
    def queue_as(*) = nil
    def set(**) = self
    def perform_later(*args)
      self.enqueued ||= []
      enqueued << args
    end
  end
end
class DirectorySyncJob < ApplicationJob; end
Dir[ROOT.join('app/models/lightek_identity/*.rb')].each { |file| require file }
require ROOT.join('app/services/lightek_identity/permissions')
require ROOT.join('app/services/lightek_identity/directory_policy')
require ROOT.join('app/services/lightek_identity/public_http')
require ROOT.join('app/services/lightek_identity/oidc')
source = ROOT.join('db/migrate/20261113210000_create_dymond_bookkeeping.rb').read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
eval(source,TOPLEVEL_BINDING)
CreateDymondBookkeeping.new.migrate(:up)
require ROOT.join('app/models/concerns/accounting_sealed_record')
Dir[ROOT.join('app/models/lightek_accounting/*.rb')].each { |file| require file }
Dir[ROOT.join('app/services/lightek_accounting/*.rb')].each { |file| require file }
class GatekeeperNode < ApplicationRecord
  belongs_to :owner,polymorphic: true
  def local? = ip_address == '127.0.0.1'
end
ActiveRecord::Schema.define do
  create_table(:gatekeeper_hosted_applications) { |t| t.integer :owner_id; t.string :name }
end
class GatekeeperHostedApplication < ApplicationRecord
  belongs_to :owner,class_name: 'User'
end
require ROOT.join('app/services/gatekeeper/hosting/access')
class EnterpriseAccountingChecks < PeoplePayrollChecks
  def self.runnable_methods = super.grep(/test_enterprise_/)
  def setup
    super
    @book = LightekAccounting::Book.create!(employer: @employer,name: 'Test business')
    @account = LightekAccounting::BankAccount.new(book: @book,name: 'Checking',opening_on: Date.new(2026,1,1))
    @account.data = {'opening_cents'=>100_000,'last_four'=>'1234'}
    @account.save!
    @accounting_access = LightekAccounting::Access.new(actor: @employer,employer: @employer)
    @income = @book.categories.find_by!(name: 'Sales')
    @expense = @book.categories.find_by!(name: 'Office')
  end
  def entry(amount,date = '2026-01-02',description = 'Private transaction',category = nil)
    row = @book.transactions.new(bank_account: @account,posted_on: date,source_key: SecureRandom.uuid,category: category)
    row.data = {'amount_cents'=>amount,'description'=>description}
    row.save!
    row
  end
  def test_enterprise_defaults_are_ready_and_do_not_overwrite_custom_departments
    custom = LightekPeople::Department.create!(employer: @employer,name: 'IT',code: 'CUSTOM',active: false)
    LightekPeople::StarterDepartments.ensure!(@employer)
    count = LightekPeople::Department.where(employer: @employer).count
    assert_equal 26,count
    LightekPeople::StarterDepartments.ensure!(@employer)
    assert_equal count,LightekPeople::Department.where(employer: @employer).count
    assert_equal 'CUSTOM',custom.reload.code
    refute custom.active?
    assert LightekPeople::Department.exists?(employer: @employer,code: 'SHIP')
    assert LightekPeople::Department.exists?(employer: @employer,code: 'RECV')
    assert_equal 'Finance',LightekPeople::Department.find_by!(employer: @employer,code: 'ACCT').parent.name
  end
  def test_enterprise_mfa_rfc_vector_enrollment_replay_and_recovery
    secret = LightekIdentity::Mfa.base32('12345678901234567890')
    assert_equal '287082',LightekIdentity::Mfa.code(secret,59/30)
    seed = LightekIdentity::Mfa.begin!(@worker.worker)
    now = Time.current
    code = LightekIdentity::Mfa.code(seed,now.to_i/30)
    recovery = LightekIdentity::Mfa.verify!(@worker.worker,code,enrolling: true,now: now)
    assert_equal 10,recovery.size
    assert LightekIdentity::Mfa.enabled?(@worker.worker)
    assert_raises(LightekIdentity::Mfa::Invalid) { LightekIdentity::Mfa.verify!(@worker.worker,code,now: now) }
    assert LightekIdentity::Mfa.verify!(@worker.worker,recovery.first,now: now)
    assert_raises(LightekIdentity::Mfa::Invalid) { LightekIdentity::Mfa.verify!(@worker.worker,recovery.first,now: now) }
    serialized=LightekIdentity::Factor.find_by!(user: @worker.worker).attributes.to_json
    refute_includes serialized,seed
    refute_includes serialized,recovery.first
  end
  def test_enterprise_directory_grants_revoke_with_membership_and_owner_transfer
    node = GatekeeperNode.create!(name: 'Worker node',owner: @employer,ip_address: '198.51.100.1',ssh_user: 'root')
    grant = LightekIdentity::ResourceGrant.create!(employer: @employer,subject: @worker,resource: node,permission: 'read')
    assert_includes Gatekeeper::Hosting::Access.nodes(@worker.worker).pluck(:id),node.id
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Access.authorize!(@worker.worker,node) }
    grant.update!(permission: 'manage')
    Gatekeeper::Hosting::Access.authorize!(@worker.worker,node)
    assert_equal [@worker.worker_id],Gatekeeper::Hosting::Access.account_ids(@worker.worker)
    @worker.update!(active: false)
    assert_empty LightekIdentity::Permissions.ids(@worker.worker,'GatekeeperNode','manage')
    @worker.update!(active: true)
    node.update!(owner: @other)
    assert_empty LightekIdentity::Permissions.ids(@worker.worker,'GatekeeperNode','manage')
    invalid = LightekIdentity::ResourceGrant.new(employer: @employer,subject: @worker,resource: node,permission: 'login')
    refute invalid.valid?
  end
  def test_enterprise_oidc_signature_nonce_issuer_audience_and_algorithm
    connection = LightekIdentity::Connection.create!(employer: @employer,slug: 'test-company',issuer: 'https://idp.example.com',authorization_endpoint: 'https://idp.example.com/auth',token_endpoint: 'https://idp.example.com/token',jwks_uri: 'https://idp.example.com/jwks',client_id: 'app')
    key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(key,kid: 'key1').export.stringify_keys
    claims = {'iss'=>connection.issuer,'aud'=>'app','exp'=>5.minutes.from_now.to_i,'iat'=>Time.current.to_i,'sub'=>'immutable-subject','nonce'=>'test-nonce'}
    LightekIdentity::PublicHttp.stub(:json,{'keys'=>[jwk]}) do
      token = JWT.encode(claims,key,'RS256',kid: 'key1')
      assert_equal 'immutable-subject',LightekIdentity::Oidc.validate!(connection: connection,token: token,nonce: 'test-nonce')['sub']
      assert_raises(LightekIdentity::Oidc::Invalid) { LightekIdentity::Oidc.validate!(connection: connection,token: token,nonce: 'wrong') }
      assert_raises(JWT::DecodeError) { LightekIdentity::Oidc.validate!(connection: connection,token: JWT.encode(claims.merge('iss'=>'https://wrong.test'),key,'RS256',kid: 'key1'),nonce: 'test-nonce') }
      assert_raises(LightekIdentity::Oidc::Invalid) { LightekIdentity::Oidc.validate!(connection: connection,token: JWT.encode(claims.merge('aud'=>['app','other'],'azp'=>'app'),key,'RS256',kid: 'key1'),nonce: 'test-nonce') }
      assert_raises(LightekIdentity::Oidc::Invalid) { LightekIdentity::Oidc.validate!(connection: connection,token: JWT.encode(claims,nil,'none'),nonce: 'test-nonce') }
    end
    assert_raises(LightekIdentity::PublicHttp::Invalid) { LightekIdentity::PublicHttp.json('http://127.0.0.1/private') }
  end
  def test_enterprise_financial_records_are_encrypted_context_bound_and_immutable
    row=entry(12345,'2026-01-02','Confidential vendor payment',@expense)
    refute_includes row.attributes.to_json,'Confidential vendor payment'
    assert_equal 12345,row.reload.amount_cents
    refute row.update(data: {'amount_cents'=>999,'description'=>'tampered'})
    assert_equal 12345,row.reload.amount_cents
    copy=entry(12345)
    copy.update_column(:sealed_data,row.sealed_data)
    assert_raises(SecurityError) { copy.reload.data }
  end
  def test_enterprise_accounting_permissions_do_not_come_from_payroll_or_management
    assert_raises(LightekAccounting::Access::Denied) { LightekAccounting::Access.new(actor: @manager.worker,employer: @employer).require! }
    assert_raises(LightekAccounting::Access::Denied) { LightekAccounting::Access.new(actor: @approver.worker,employer: @employer).require! }
    @worker.update!(accounting_access: 'bookkeeper')
    access=LightekAccounting::Access.new(actor: @worker.worker,employer: @employer)
    assert access.require!(:write)
    assert_raises(LightekAccounting::Access::Denied) { access.require!(:review) }
    @worker.update!(active: false)
    assert_raises(LightekAccounting::Access::Denied) { access.require! }
  end
  def test_enterprise_csv_mapping_exact_reimports_and_ambiguous_duplicates
    raw="Date,Description,Amount,Reference\n2026-01-02,Customer payment,500.00,P1\n2026-01-03,Office,-100.00,P2\n"
    record=LightekAccounting::Imports.preview!(access: @accounting_access,account: @account,raw: raw)
    assert_empty record.data['preview']
    LightekAccounting::Imports.map!(access: @accounting_access,record: record,mapping: {'date'=>'0','description'=>'1','amount'=>'2','reference'=>'3','date_format'=>'iso','mode'=>'signed'})
    LightekAccounting::Imports.commit!(access: @accounting_access,record: record)
    LightekAccounting::Imports.commit!(access: @accounting_access,record: record)
    assert_equal 2,@book.transactions.count
    duplicate=LightekAccounting::Imports.preview!(access: @accounting_access,account: @account,raw: raw,mapping: {'date'=>'0','description'=>'1','amount'=>'2','reference'=>'3','date_format'=>'iso','mode'=>'signed'})
    LightekAccounting::Imports.commit!(access: @accounting_access,record: duplicate)
    assert_equal 2,@book.transactions.count
    ambiguous="Date,Description,Amount\n2026-01-02,Customer payment,500.00\n"
    record=LightekAccounting::Imports.preview!(access: @accounting_access,account: @account,raw: ambiguous,mapping: {'date'=>'0','description'=>'1','amount'=>'2','date_format'=>'iso','mode'=>'signed'})
    assert_raises(ArgumentError) { LightekAccounting::Imports.commit!(access: @accounting_access,record: record) }
    assert_equal 2,@book.transactions.count
  end
  def test_enterprise_ofx_and_money_precision_fail_closed
    raw='<OFX><BANKTRANLIST><STMTTRN><DTPOSTED>20260102120000[-5:EST]<TRNAMT>-25.99<FITID>A1<NAME>Office<MEMO>Supplies</STMTTRN></BANKTRANLIST></OFX>'
    table=LightekAccounting::StatementParser.table(raw)
    rows=LightekAccounting::StatementParser.rows(table,table[:default_mapping])
    assert_equal(-2599,rows.first['amount_cents'])
    assert_equal '2026-01-02',rows.first['date']
    assert_raises(ArgumentError) { LightekAccounting::StatementParser.table('<!DOCTYPE OFX [<!ENTITY x SYSTEM "file:///etc/passwd">]>'+raw) }
    assert_equal(-123456,LightekAccounting::Money.cents!('($1,234.56)'))
    assert_equal(-1234,LightekAccounting::Money.cents!('-$12.34'))
    %w[1.001 1e9 12,34 NaN].each { |value| assert_raises(ArgumentError) { LightekAccounting::Money.cents!(value) } }
  end
  def test_enterprise_reconciliation_proves_outstanding_and_locks_closed_period
    a=entry(50_000,'2026-01-02','Deposit')
    b=entry(-20_000,'2026-01-03','Cleared check')
    entry(-5_000,'2026-01-04','Outstanding check')
    args={account: @account,first: Date.new(2026,1,1),last: Date.new(2026,1,31),starting: 100_000,ending: 130_000,selected: [a.id,b.id]}
    proof=LightekAccounting::Reconcile.proof(**args)
    assert_equal 0,proof['cleared_difference_cents']
    assert_equal 0,proof['book_difference_cents']
    assert_equal 5_000,proof['outstanding_checks_cents']
    assert_raises(ArgumentError) { LightekAccounting::Reconcile.finalize!(access: @accounting_access,**args.merge(ending: 130_001)) }
    record=LightekAccounting::Reconcile.finalize!(access: @accounting_access,**args)
    assert_equal record.id,a.reload.reconciliation_id
    assert_raises(ActiveRecord::RecordInvalid) { entry(100,'2026-01-15','Late entry') }
    LightekAccounting::Reconcile.reopen!(access: @accounting_access,record: record)
    assert_equal 'superseded',record.reload.status
    assert_equal 130_000,record.data['ending_cents']
    assert_nil a.reload.reconciliation_id
    assert entry(100,'2026-01-15','Reviewed late entry')
  end
  def test_enterprise_profit_loss_excludes_transfers_and_aggregates_deduction_rounding
    meals=@book.categories.create!(name: 'Meals',kind: 'expense',deduction_bps: 5000,schedule_code: '24b')
    transfer=@book.categories.create!(name: 'Transfer',kind: 'transfer')
    entry(10000,'2026-01-02','Income',@income)
    entry(-1,'2026-01-03','Meal1',meals)
    entry(-1,'2026-01-04','Meal2',meals)
    entry(99999,'2026-01-05','Transfer',transfer)
    report=LightekAccounting::Reports.profit_loss(book: @book,first: Date.new(2026,1,1),last: Date.new(2026,12,31))
    assert_equal 9998,report['profit_cents']
    assert_equal 9999,report['tax_profit_cents']
    assert_equal 1,report['groups'].find { |g| g['name']=='Meals' }['tax_cents']
  end
  def test_enterprise_tax_rates_se_cap_safe_harbor_and_version
    assert_equal 580_000,LightekAccounting::TaxEstimate.rate_tax(5_040_000,'single')
    result=LightekAccounting::TaxEstimate.calculate({'year'=>2026,'filing_status'=>'single','profit_cents'=>10_000_000})
    assert_equal 1_412_955,result['self_employment_tax_cents']
    assert_equal 706_478,result['se_deduction_cents']
    assert_equal '2027-01-15',result['quarters'].last['due_on']
    capped=LightekAccounting::TaxEstimate.calculate({'year'=>2026,'filing_status'=>'single','profit_cents'=>10_000_000,'social_security_wages_cents'=>18_450_000})
    assert_equal 267_815,capped['self_employment_tax_cents']
    zero=LightekAccounting::TaxEstimate.calculate({'year'=>2026,'filing_status'=>'single','profit_cents'=>100_000_000,'prior_tax_cents'=>0,'prior_full_year'=>true})
    assert_equal 0,zero['annual_required_estimates_cents']
    assert_raises(ArgumentError) { LightekAccounting::TaxEstimate.calculate({'year'=>2027,'filing_status'=>'single','profit_cents'=>1}) }
  end
  def test_enterprise_native_formula_subset_and_security
    schema={'sheets'=>[{'name'=>'Ledger','cells'=>{'A1'=>{'value'=>'0.1','type'=>'number'},'A2'=>{'value'=>'0.2','type'=>'number'},'B1'=>{'formula'=>'SUM(A1:A2)'},'B2'=>{'formula'=>'IF(0,1/0,ROUND(B1,2))'},'B3'=>{'formula'=>'IFERROR(1/0,99)'},'B4'=>{'formula'=>'HYPERLINK("https://evil.test","click")'},'C1'=>{'formula'=>'IFERROR(C1,0)'}}}]}
    engine=LightekAccounting::SheetFormula.new(schema)
    assert_equal BigDecimal('0.3'),engine.cell('Ledger','B1')
    assert_equal BigDecimal('0.3'),engine.cell('Ledger','B2')
    assert_equal BigDecimal('99'),engine.cell('Ledger','B3')
    assert_raises(LightekAccounting::SheetFormula::Unsupported) { engine.cell('Ledger','B4') }
    assert_raises(LightekAccounting::SheetFormula::Unsupported) { engine.cell('Ledger','C1') }
    assert_raises(ArgumentError) { LightekAccounting::WorkbookSchema.table(schema,'Ledger',header_row: -1) }
  end
end
class EnterpriseAccountingChecks
  def xlsx_fixture(extra = {})
    serial=(Date.new(2026,1,2)-Date.new(1899,12,30)).to_i
    parts={
      '[Content_Types].xml'=>'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>',
      'xl/workbook.xml'=>'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Ledger" sheetId="1" r:id="r1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels'=>'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Target="worksheets/sheet1.xml" Type="worksheet"/></Relationships>',
      'xl/styles.xml'=>'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>',
      'xl/worksheets/sheet1.xml'=>"<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Date</t></is></c><c r=\"B1\" t=\"inlineStr\"><is><t>Description</t></is></c><c r=\"C1\" t=\"inlineStr\"><is><t>Amount</t></is></c></row><row r=\"2\"><c r=\"A2\" s=\"1\"><v>#{serial}</v></c><c r=\"B2\" t=\"inlineStr\"><is><t>Client receipt</t></is></c><c r=\"C2\"><f>ROUND(100/4,2)</f><v>999999</v></c></row></sheetData></worksheet>"
    }.merge(extra)
    Zip::OutputStream.write_buffer do |zip|
      parts.each { |name,contents| zip.put_next_entry(name);zip.write(contents) }
    end.string
  end
  def test_enterprise_xlsx_structure_dates_calculation_and_external_content_rejection
    schema=LightekAccounting::WorkbookSchema.parse(xlsx_fixture,filename: 'client.xlsx')
    assert_equal 'Ledger',schema['sheets'].first['name']
    table=LightekAccounting::WorkbookSchema.table(schema,'Ledger')
    assert_equal %w[Date Description Amount],table[:headers]
    assert_equal ['2026-01-02','Client receipt','25.0'],table[:rows].first
    assert_raises(ArgumentError) { LightekAccounting::WorkbookSchema.parse(xlsx_fixture('xl/vbaProject.bin'=>'unsafe'),filename: 'client.xlsx') }
    external='<Relationships><Relationship Id="r1" Target="https://evil.test" TargetMode="External"/></Relationships>'
    assert_raises(ArgumentError) { LightekAccounting::WorkbookSchema.parse(xlsx_fixture('xl/_rels/workbook.xml.rels'=>external),filename: 'client.xlsx') }
  end
  def test_enterprise_workbook_converts_to_native_categories_and_rules_idempotently
    schema=LightekAccounting::WorkbookSchema.parse("Name,Kind,Deductible Percent\nResearch expenses,expense,100\n",filename: 'categories.csv')
    record=LightekAccounting::Workbook.new(book: @book,actor: @employer,name: 'Native blueprint');record.data=schema;record.save!
    first=LightekAccounting::WorkbookConversion.apply!(access: @accounting_access,workbook: record,sheet: 'Sheet1',header_row: 1,target: 'categories')
    second=LightekAccounting::WorkbookConversion.apply!(access: @accounting_access,workbook: record.reload,sheet: 'Sheet1',header_row: 1,target: 'categories')
    assert_equal first,second
    assert_equal 1,@book.categories.where(name: 'Research expenses').count
    rule_schema=LightekAccounting::WorkbookSchema.parse("Keyword,Category,Priority\nLAB,Research expenses,10\n",filename: 'rules.csv')
    record.update!(data: rule_schema)
    LightekAccounting::WorkbookConversion.apply!(access: @accounting_access,workbook: record,sheet: 'Sheet1',header_row: 1,target: 'keyword_rules')
    assert_equal 'Research expenses',LightekAccounting::Rules.category_for(@book,'Lab supplier').name
  end
  def test_enterprise_oidc_state_browser_binding_and_consumption
    connection=LightekIdentity::Connection.create!(employer: @employer,slug: 'company-one',issuer: 'https://idp.example.com',authorization_endpoint: 'https://idp.example.com/auth',token_endpoint: 'https://idp.example.com/token',jwks_uri: 'https://idp.example.com/jwks',client_id: 'app')
    seed=LightekIdentity::Mfa.begin!(@worker.worker)
    now=Time.current
    LightekIdentity::Mfa.verify!(@worker.worker,LightekIdentity::Mfa.code(seed,now.to_i/30),enrolling: true,now: now)
    LightekIdentity::Subject.create!(connection: connection,user: @worker.worker,subject: 'known-subject')
    url=LightekIdentity::Oidc.start!(connection: connection,browser: 'browser-bound',redirect_uri: 'https://app.example.com/callback')
    query=URI.decode_www_form(URI.parse(url).query).to_h
    assert_equal 'S256',query['code_challenge_method']
    refute query.key?('code_verifier')
    attempt=LightekIdentity::LoginAttempt.last
    refute_includes attempt.secret_box.to_json,query['nonce']
    assert_raises(LightekIdentity::Oidc::Invalid) { LightekIdentity::Oidc.finish!(state: query['state'],code: 'code',browser: 'wrong') }
    assert_nil attempt.reload.consumed_at
    LightekVault::Service.payload={'client_secret'=>'test-secret'}
    LightekIdentity::PublicHttp.stub(:json,{'id_token'=>'fixture'}) do
      LightekIdentity::Oidc.stub(:validate!,{'sub'=>'known-subject'}) do
        user,returned,_=LightekIdentity::Oidc.finish!(state: query['state'],code: 'code',browser: 'browser-bound')
        assert_equal @worker.worker_id,user.id
        assert_equal connection.id,returned.id
        assert_raises(LightekIdentity::Oidc::Invalid) { LightekIdentity::Oidc.finish!(state: query['state'],code: 'code',browser: 'browser-bound') }
      end
    end
  end
end

class EnterpriseAccountingChecks
  def test_enterprise_excel_precedence_and_formula_review_boundaries
    cells={'A1'=>{'value'=>'100','type'=>'number'},'B1'=>{'formula'=>'-2^2'},'B2'=>{'formula'=>'2^3^2'},'B3'=>{'formula'=>'COUNTIF(A1:A1,"100")'},'B4'=>{'formula'=>'COUNTIF(A1:A1,"1*")'},'B5'=>{'formula'=>'ABS(1,2)'},'B6'=>{'formula'=>'"hello"="HELLO"'},'B7'=>{'formula'=>'100&" dollars"'}}
    engine=LightekAccounting::SheetFormula.new({'sheets'=>[{'name'=>'Sheet1','cells'=>cells}]})
    assert_equal BigDecimal('4'),engine.cell('Sheet1','B1')
    assert_equal BigDecimal('64'),engine.cell('Sheet1','B2')
    assert_equal BigDecimal('1'),engine.cell('Sheet1','B3')
    assert_raises(LightekAccounting::SheetFormula::Unsupported) { engine.cell('Sheet1','B4') }
    assert_raises(LightekAccounting::SheetFormula::Unsupported) { engine.cell('Sheet1','B5') }
    assert_equal true,engine.cell('Sheet1','B6')
    assert_equal '100 dollars',engine.cell('Sheet1','B7')
    25.times { |i| cells["C#{i+1}"]={'formula'=>'SUM(A1:A10000)'} }
    assert_raises(LightekAccounting::SheetFormula::Unsupported) { 25.times { |i| engine.cell('Sheet1',"C#{i+1}") } }
  end
end

if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
  class EnterpriseAccountingChecks
    def concurrent_enterprise_calls(&block)
      ready,go,results=Queue.new,Queue.new,Queue.new
      threads=2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            begin
              results << block.call
            rescue StandardError => error
              results << error
            end
          end
        end
      end
      2.times { ready.pop };2.times { go << true };threads.each(&:join)
      2.times.map { results.pop }
    end
    def test_enterprise_postgresql_parallel_import_commits_once
      record=LightekAccounting::Imports.preview!(access: @accounting_access,account: @account,raw: "Date,Description,Amount\n2026-01-02,Parallel receipt,50.00\n",mapping: {'date'=>'0','description'=>'1','amount'=>'2','mode'=>'signed','date_format'=>'iso'})
      results=concurrent_enterprise_calls do
        access=LightekAccounting::Access.new(actor: User.find(@employer.id),employer: User.find(@employer.id))
        LightekAccounting::Imports.commit!(access: access,record: LightekAccounting::Import.find(record.id))
        :ok
      end
      assert_equal [:ok,:ok],results
      assert_equal 1,@account.transactions.count
      assert_equal 'committed',record.reload.status
    end
    def test_enterprise_postgresql_parallel_finalization_has_one_proof
      row=entry(5000)
      results=concurrent_enterprise_calls do
        access=LightekAccounting::Access.new(actor: User.find(@employer.id),employer: User.find(@employer.id))
        LightekAccounting::Reconcile.finalize!(access: access,account: LightekAccounting::BankAccount.find(@account.id),first: Date.new(2026,1,1),last: Date.new(2026,1,31),starting: 100000,ending: 105000,selected: [row.id])
        :ok
      end
      assert_equal 1,results.count(:ok)
      assert_equal 1,results.count { |r| r.is_a?(ArgumentError) }
      assert_equal 1,@account.reconciliations.where(status: 'final').count
      assert_equal @account.reconciliations.last.id,row.reload.reconciliation_id
    end
  end
end
