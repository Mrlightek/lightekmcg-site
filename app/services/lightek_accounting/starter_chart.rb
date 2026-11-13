module LightekAccounting
  class StarterChart
    ENTRIES = [
      ['Sales','income',10000],['Other business income','income',10000],
      ['Advertising','expense',10000],['Vehicle expenses','expense',10000],
      ['Merchant and professional fees','expense',10000],['Contract labor','expense',10000],
      ['Business insurance','expense',10000],['Office','expense',10000],
      ['Rent','expense',10000],['Repairs and maintenance','expense',10000],
      ['Supplies','expense',10000],['Taxes and licenses','expense',10000],
      ['Travel','expense',10000],['Meals','expense',5000],['Utilities','expense',10000],
      ['Wages','expense',10000],['Other expenses','expense',10000],
      ['Inter-account transfer','transfer',0],['Owner contributions and draws','equity',0]
    ].freeze
    def self.install!(book)
      ENTRIES.each do |name,kind,bps|
        book.categories.find_or_create_by!(name: name) { |category| category.kind=kind;category.deduction_bps=bps }
      end
    end
  end
end
