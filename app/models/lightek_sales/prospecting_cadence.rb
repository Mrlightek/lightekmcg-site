# frozen_string_literal: true

module LightekSales
  class ProspectingCadence < ApplicationRecord
    self.table_name = 'lightek_sales_prospecting_cadences'

    belongs_to :site, class_name: 'DymondSite::Site'
    validates :name, presence: true, length: {maximum: 120}, uniqueness: {scope: :site_id}
    validates :steps, presence: true

    def self.parse_steps(rows)
      unless rows.is_a?(Array) && rows.size.between?(1, 20)
        raise ArgumentError, 'Enter between 1 and 20 cadence steps.'
      end

      steps = rows.map do |row|
        days, title = row.values_at('days', 'title').map { |value| value.to_s.strip }
        unless days.match?(/\A[0-9]{1,3}\z/) && title.present? && title.length <= 300
          raise ArgumentError, 'Enter a day and an action of up to 300 characters for every step.'
        end
        {'days' => days.to_i, 'title' => title}
      end
      unless steps.each_cons(2).all? { |earlier, later| earlier['days'] <= later['days'] }
        raise ArgumentError, 'List cadence steps in order from earliest to latest.'
      end

      steps
    end
  end
end
