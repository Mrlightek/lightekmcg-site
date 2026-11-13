module LightekPeople
  class StarterDepartments
    VERSION = 1
    ENTRIES = [
      ['EXEC','Executive Leadership',nil,[]],
      ['OPS','Operations','EXEC',[]],
      ['FIN','Finance','EXEC',[]],
      ['ACCT','Accounting','FIN',%w[ACCOUNTING]],
      ['PAY','Payroll','FIN',[]],
      ['HR','People & Human Resources','EXEC',['Human Resources','HR','People']],
      ['BEN','Benefits & Compensation','HR',[]],
      ['RECRUIT','Talent Acquisition','HR',[]],
      ['IT','Information Technology','EXEC',['IT','Technology']],
      ['INFRA','Infrastructure & Network','IT',[]],
      ['HELP','IT Service Desk','IT',[]],
      ['SEC','Information Security','IT',[]],
      ['CS','Customer Service','OPS',['Customer Support','Customer Success']],
      ['SALES','Sales','EXEC',[]],
      ['MKT','Marketing & Communications','EXEC',['Marketing']],
      ['LEGAL','Legal & Compliance','EXEC',['Legal','Compliance']],
      ['RISK','Risk & Internal Audit','EXEC',[]],
      ['PRODUCT','Product Management','EXEC',[]],
      ['ENG','Engineering & Development','EXEC',['Engineering']],
      ['DATA','Data & Analytics','IT',[]],
      ['PROC','Procurement & Vendor Management','OPS',[]],
      ['SHIP','Shipping & Logistics','OPS',['Shipping']],
      ['RECV','Receiving & Inventory','OPS',['Receiving']],
      ['FAC','Facilities & Administration','OPS',[]],
      ['PMO','Project Management Office','OPS',[]],
      ['QA','Quality Assurance','OPS',[]]
    ].freeze
    def self.ensure!(employer)
      employer.with_lock do
        LightekIdentity::OrganizationPolicy.find_or_create_by!(employer: employer) if defined?(LightekIdentity::OrganizationPolicy)
        return if employer.people_template_version >= VERSION
        scope = Department.where(employer: employer)
        resolved = {}
        ENTRIES.each do |code,name,parent,aliases|
          names = ([name] + aliases).map(&:downcase)
          existing = scope.find_by(code: code) || scope.where('LOWER(name) IN (?)',names).first
          record = existing || scope.create!(name: name,code: code,parent: resolved[parent])
          resolved[code] = record
        end
        employer.update_column(:people_template_version,VERSION)
      end
    end
  end
end
