module LightekGrowth
  module Performance
    module Recommendations
      def self.call(site)
        # A bounded recent-comparison prompt, not a claim of complete backlog coverage.
        row = Comparison.where(site: site).where('starts_on <= ?', Date.current).order(id: :desc).first
        review = row&.reviews&.order(id: :desc)&.first
        due = row && (!review || review.measured_at < 1.day.ago)
        {'performance_review_due' => due ? 1 : 0, 'performance_comparison_id' => row&.id, 'performance_review_id' => review&.id}
      end
    end
  end
end
