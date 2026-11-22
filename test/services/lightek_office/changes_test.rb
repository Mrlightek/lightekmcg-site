# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../app/services/lightek_office/changes'

class LightekOfficeChangesTest < Minitest::Test
  def test_non_overlapping_changes_are_preserved
    assert_equal "Café\nTea\nWater", merge("Coffee\nJuice\nWater", "Café\nJuice\nWater", "Coffee\nTea\nWater")
    assert_equal "A,2\nB,3", merge("A,1\nB,1", "A,2\nB,1", "A,1\nB,3")
  end

  def test_overlapping_changes_are_rejected
    assert_nil merge('Friday', 'Monday', 'Sunday')
    assert_nil merge('Monday', '+Monday', '-Monday')
  end

  def test_disjoint_rich_text_edits_merge_without_rewriting_the_markup
    assert_equal '<div>Launch now</div><div>Costs $99</div>',
      merge('<div>Launch soon</div><div>Costs $10</div>', '<div>Launch now</div><div>Costs $10</div>',
        '<div>Launch soon</div><div>Costs $99</div>', rich_text: true)
  end

  def test_concurrent_rich_text_merges_reject_markup_and_entity_edits
    assert_nil merge('<div>A</div><div>B</div>', '<div><b>A</b></div><div>B</div>', '<div>A</div><div>C</div>', rich_text: true)
    assert_nil merge('<div>&lt;</div><div>B</div>', '<div>&gt;</div><div>B</div>', '<div>&lt;</div><div>C</div>', rich_text: true)
  end

  private

  def merge(*parts, **options)
    LightekOffice::Changes.merge_text(*parts, **options)
  end
end
