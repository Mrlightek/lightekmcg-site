# frozen_string_literal: true
module NevaehIntelligences
  module Islamic
    module Library
      module_function
      def search(query:, source_id: nil)
        text = query.to_s.strip
        raise ArgumentError, 'Search needs 1–200 characters' unless text.length.between?(1, 200)
        scope = NevaehIslamicPassage.joins(:nevaeh_islamic_source).includes(:nevaeh_islamic_source)
          .where(nevaeh_islamic_sources: {status: 'reviewed'})
        scope = scope.where(nevaeh_islamic_source_id: source_id) if source_id.present?
        exact = scope.where(reference: text).order(:nevaeh_islamic_source_id).limit(30).to_a
        return exact unless exact.empty?
        # Literal substring search; SQL wildcard characters in the query are escaped.
        scope.where('LOWER(body) LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(text.downcase)}%")
          .order(:nevaeh_islamic_source_id, :id).limit(30).to_a
      end
      def lookup(source_id:, reference:)
        NevaehIslamicPassage.joins(:nevaeh_islamic_source)
          .where(nevaeh_islamic_sources: {status: 'reviewed'})
          .find_by!(nevaeh_islamic_source_id: source_id, reference: reference).citation
      end
    end
  end
end
