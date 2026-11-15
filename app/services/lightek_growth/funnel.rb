module LightekGrowth
  class Funnel
    attr_reader :site, :from, :to
    def initialize(site:, from:, to:)
      @site, @from, @to = site, Date.iso8601(from.to_s), Date.iso8601(to.to_s)
      raise ArgumentError, 'Choose a date range of up to 366 days.' if @to < @from || (@to - @from) > 365
    end
    def visits = Visit.where(site: site, created_at: from.beginning_of_day..to.end_of_day)
    def stages(link: nil)
      stage_groups.to_h { |label, counts| [label, link ? counts.fetch(link.id, 0) : counts.values.sum] }
    end
    def stage_groups
      @stage_groups ||= begin
        ids = visits.select(:id)
        inquiries = WebsiteTemplateInquiry.where(site: site, growth_visit_id: ids)
        leads = LightekSales::Lead.where(site: site, growth_visit_id: ids)
        deals = LightekSales::Opportunity.where(site: site, growth_visit_id: ids)
        orders = self.orders
        paid = orders.where.not(paid_at: nil)
        delivered = paid.where.not(fulfilled_at: nil).or(paid.where.not(provisioned_at: nil))
        {'Tracked visits' => visits.group(:link_id).count}.merge(
          {'Inquiry' => inquiries, 'Lead' => leads, 'Deal' => deals, 'Order' => orders,
           'Confirmed payment' => paid, 'Delivery recorded' => delivered}.transform_values do |scope|
            scope.joins(:growth_visit).group('lightek_growth_visits.link_id').distinct.count(:growth_visit_id)
          end
        )
      end
    end
    def orders
      LightekCommerce::Order.where(site: site, growth_visit_id: visits.select(:id))
    end
    def money
      paid = orders.where.not(paid_at: nil).where(currency: 'usd')
      {paid_orders: paid.count, collected_cents: paid.sum(:total_cents), refunded_cents: paid.sum(:refunded_cents)}
    end
    def unknown
      {
        inquiries: WebsiteTemplateInquiry.where(site: site, growth_visit_id: nil, created_at: from.beginning_of_day..to.end_of_day).count,
        leads: LightekSales::Lead.where(site: site, growth_visit_id: nil, created_at: from.beginning_of_day..to.end_of_day).count,
        deals: LightekSales::Opportunity.where(site: site, growth_visit_id: nil, created_at: from.beginning_of_day..to.end_of_day).count,
        paid_orders: LightekCommerce::Order.where(site: site, growth_visit_id: nil, paid_at: from.beginning_of_day..to.end_of_day).count
      }
    end
  end
end
