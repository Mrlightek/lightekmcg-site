module LightekAccounting
  # Published 2026 Form 1040-ES rate schedules; ordinary-income reserve worksheet.
  # It is not a tax return, payment instruction or proof of IRS submission.
  class TaxEstimate
    VERSION = 'irs-1040es-2026-v1'.freeze
    SOURCE = 'https://www.irs.gov/pub/irs-pdf/f1040es.pdf'.freeze
    RATES = [10,12,22,24,32,35,37].freeze
    LIMITS = {
      'single'=>[12400,50400,105700,201775,256225,640600],
      'joint'=>[24800,100800,211400,403550,512450,768700],
      'separate'=>[12400,50400,105700,201775,256225,384350],
      'head'=>[17700,67450,105700,201750,256200,640600]
    }.freeze
    DEDUCTIONS = {'single'=>16100,'joint'=>32200,'separate'=>16100,'head'=>24150}.freeze
    def self.rate_tax(taxable,status)
      previous, total = 0, 0.to_r
      (LIMITS.fetch(status).map { |v| v * 100 } + [nil]).each_with_index do |ceiling,index|
        width = [taxable,ceiling || taxable].min - previous
        break if width <= 0
        total += Rational(width * RATES[index],100)
        previous = ceiling if ceiling
      end
      total.round
    end
    def self.calculate(inputs, as_of: Date.current)
      p = inputs.stringify_keys
      raise ArgumentError, 'This version supports tax year 2026 only' unless Integer(p.fetch('year')) == 2026
      status = p.fetch('filing_status')
      raise ArgumentError, 'Choose a supported filing status' unless LIMITS.key?(status)
      cents = ->(key,default=0) { Money.integer!(p.fetch(key,default)).tap { |value| raise ArgumentError, 'Tax inputs other than profit cannot be negative' if key != 'profit_cents' && value.negative? } }
      profit = cents.call('profit_cents')
      earnings = [Rational(profit * 9235,10000).round,0].max
      ss_wages, medicare_wages = cents.call('social_security_wages_cents'), cents.call('medicare_wages_cents')
      spouse_wages = cents.call('spouse_medicare_wages_cents')
      raise ArgumentError, 'Spouse wages require joint filing in this worksheet' if spouse_wages.positive? && status != 'joint'
      social_cap = [18_450_000 - ss_wages,0].max
      se = earnings >= 40_000 ? (Rational([earnings,social_cap].min * 124,1000) + Rational(earnings * 29,1000)).round : 0
      se_deduction = Rational(se,2).round
      threshold = {'single'=>20_000_000,'head'=>20_000_000,'joint'=>25_000_000,'separate'=>12_500_000}.fetch(status)
      additional_medicare = Rational([earnings + medicare_wages + spouse_wages - threshold,0].max * 9,1000).round
      deductions = cents.call('deductions_cents',DEDUCTIONS.fetch(status) * 100)
      taxable = [profit + cents.call('other_ordinary_income_cents') - se_deduction - cents.call('agi_adjustments_cents') - deductions,0].max
      income_tax = [rate_tax(taxable,status) - cents.call('nonrefundable_credits_cents'),0].max
      total_tax = income_tax + se + additional_medicare + cents.call('other_taxes_cents')
      net_tax = [total_tax - cents.call('refundable_credits_cents'),0].max
      withholding = cents.call('withholding_cents')
      expected_balance = [net_tax - withholding,0].max
      current_target = Rational(net_tax * 90,100).round
      prior_target = nil
      if p['prior_full_year'] == true && p.key?('prior_tax_cents')
        prior_rate = cents.call('prior_agi_cents') > (status == 'separate' ? 7_500_000 : 15_000_000) ? 110 : 100
        prior_target = Rational(cents.call('prior_tax_cents') * prior_rate,100).round
      end
      annual_required = expected_balance < 100_000 ? 0 : [[current_target,prior_target].compact.min - withholding,0].max
      payments = Array(p['payments']).map do |payment|
        date = Date.iso8601(payment.fetch('date'))
        raise ArgumentError, 'Record only payments already made for this tax year' if date > as_of || date < Date.new(2026,1,1)
        amount = Money.integer!(payment.fetch('amount_cents'))
        raise ArgumentError, 'Payments cannot be negative' if amount.negative?
        {'date'=>date,'amount_cents'=>amount}
      end
      due_dates = %w[2026-04-15 2026-06-15 2026-09-15 2027-01-15].map { |d| Date.iso8601(d) }
      quarters = due_dates.each_with_index.map do |date,index|
        cumulative = (Rational(annual_required * (index + 1),4)).ceil
        paid = payments.select { |payment| payment['date'] <= date }.sum { |payment| payment['amount_cents'] }
        {'due_on'=>date.iso8601,'cumulative_required_cents'=>cumulative,'cumulative_paid_cents'=>paid,'shortfall_cents'=>[cumulative-paid,0].max}
      end
      paid_so_far = payments.select { |payment| payment['date'] <= as_of }.sum { |payment| payment['amount_cents'] }
      {'version'=>VERSION,'source'=>SOURCE,'taxable_ordinary_income_cents'=>taxable,'income_tax_cents'=>income_tax,
        'self_employment_tax_cents'=>se,'se_deduction_cents'=>se_deduction,'additional_medicare_cents'=>additional_medicare,
        'annual_tax_cents'=>net_tax,'annual_required_estimates_cents'=>annual_required,
        'full_liability_reserve_cents'=>[expected_balance-paid_so_far,0].max,'quarters'=>quarters,
        'scope'=>'Ordinary-income US sole-proprietor projection. Supply reviewed adjustments/deductions/credits and other taxes; excludes automatic capital-gain, AMT, QBI, multi-person SE, state/local and annualized-income calculations.'}
    end
  end
end
