require 'test_helper'

class LightekOffice::ContentTest < ActiveSupport::TestCase
  test 'spreadsheets evaluate native formulas and sanitize text on CSV export' do
    source = "2,3,=SUM(A1:B1)\n\"=A1+B1\",5,@unsafe\n=1/0,-7,+other\n"
    assert_equal [['2', '3', '5'], ['5', '5', '@unsafe'], ['#ERROR', '-7', '+other']],
      LightekOffice::Content.calculate(source)
    assert_includes LightekOffice::Content.csv(source), "'@unsafe"
    assert_includes LightekOffice::Content.csv(source), "'+other"
    assert_raises(ArgumentError) { LightekOffice::Content.validate!('spreadsheet', ("1\n" * 101)) }
  end

  test 'presentations retain slide order and text from the source' do
    slides = LightekOffice::Content.slides("Studio launch\nOpening remarks\n---\nDistribution\nNext steps")
    assert_equal [['Studio launch', 'Opening remarks'], ['Distribution', 'Next steps']], slides
  end
end
