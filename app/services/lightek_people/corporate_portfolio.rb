# frozen_string_literal: true

module LightekPeople
  class CorporatePortfolio
    DIVISIONS = {
      "MCG-FILM" => ["Film & Studios", { "MCG-PICS" => "Lightek Pictures", "MCG-PROD" => "Lightek Studio Productions" }],
      "MCG-TV" => ["Television Networks", { "MCG-ORIG" => "Scripted & Unscripted Originals", "MCG-PROG" => "Programming & Acquisitions" }],
      "MCG-NEWS" => ["News & Local Media", { "MCG-NEWSROOM" => "Newsroom", "MCG-LOCAL" => "Local Programming" }],
      "MCG-SPORT" => ["Sports & Live Events", { "MCG-SPORTPROD" => "Sports Production", "MCG-EVENTS" => "Live Events & Rights" }],
      "MCG-ANIM" => ["Animation & Games", { "MCG-ANIMATION" => "Animation Studio", "MCG-GAMES" => "Interactive & Games" }],
      "MCG-STREAM" => ["Streaming & Platforms", { "MCG-OCTAVIA" => "Octavia TV", "MCG-STUDIO" => "Lightek Studio", "MCG-PLATFORMS" => "Platform Product & Engineering" }],
      "MCG-DIST" => ["Distribution & Affiliate Operations", { "MCG-CARRIAGE" => "Channel Carriage", "MCG-OPS" => "Network Operations", "MCG-AFFILIATE" => "Affiliate Relations" }],
      "MCG-ADS" => ["Advertising & Audience Measurement", { "MCG-ADSALES" => "Ad Sales & Partnerships", "MCG-ADOPS" => "Ad Operations", "MCG-AUDIENCE" => "Audience Research & Measurement" }]
    }.freeze

    def self.install!(employer)
      StarterDepartments.ensure!(employer)
      employer.with_lock do
        departments = Department.where(employer: employer)
        executive = departments.find_by(code: "EXEC") || departments.find_by(name: "Executive Leadership") ||
          departments.create!(code: "EXEC", name: "Executive Leadership")
        DIVISIONS.each do |code, (name, units)|
          division = departments.find_or_create_by!(code: code) { |record| record.assign_attributes(name: name, parent: executive) }
          units.each do |unit_code, unit_name|
            departments.find_or_create_by!(code: unit_code) { |record| record.assign_attributes(name: unit_name, parent: division) }
          end
        end
      end
    end
  end
end
