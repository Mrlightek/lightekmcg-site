# frozen_string_literal: true
class NevaehIslamicPassage < ApplicationRecord
  belongs_to :nevaeh_islamic_source, counter_cache: :passages_count
  validates :reference, :body, :sha256, presence: true
  validates :reference, length: {maximum: 200}
  validates :body, length: {maximum: 100_000}
  before_update do
    errors.add(:base, 'Source passages are immutable; import a new edition')
    throw :abort
  end
  def citation
    source = nevaeh_islamic_source
    {source_id: source.id, reference: reference, text: body, kind: source.kind,
      collection: source.name, edition: source.edition, language: source.language,
      tradition: source.tradition, translator: source.translator, narrator: narrator,
      assessments: assessments, attribution: source.attribution, source_url: source.source_url,
      reviewer_id: source.reviewer_id, reviewed_at: source.reviewed_at,
      passage_sha256: sha256, source_sha256: source.sha256, generated: false}
  end
end
