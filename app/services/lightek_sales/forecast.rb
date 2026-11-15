# frozen_string_literal: true
module LightekSales
  class Forecast
    # Each currency is independent. This is an estimate based on expected close
    # dates and user-entered probabilities, not a financial/revenue report.
    def self.call(scope, month: Date.current.beginning_of_month)
      scope.where(close_on: month.beginning_of_month..month.end_of_month).group(:currency).pluck(:currency).sort.map do |currency|
        period = scope.where(currency: currency, close_on: month.beginning_of_month..month.end_of_month)
        open = period.open_pipeline.where.not(forecast_category: 'omitted')
        {currency: currency, open_cents: open.sum(:amount_cents),
         weighted_cents: Rational(open.sum('amount_cents * probability'), 100).round,
         commit_cents: open.where(forecast_category: 'commit').sum(:amount_cents),
         best_case_cents: open.where(forecast_category: %w[best_case commit]).sum(:amount_cents),
         won_cents: period.where(stage: 'closed_won').sum(:amount_cents),
         lost_cents: period.where(stage: 'closed_lost').sum(:amount_cents)}
      end
    end
  end
end
