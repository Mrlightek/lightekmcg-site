# frozen_string_literal: true
module LightekDesign
  # The same section works on Lightek's website and on independent customer installations.
  # It is a real Dymond Site section, not a second page builder.
  module CommerceSections
    module_function

    def definitions
      [{
        "kind" => "lightek_product_grid",
        "fields" => [
          {"name" => "heading", "label" => "Heading", "type" => "text"},
          {"name" => "intro", "label" => "Introduction", "type" => "text"}
        ],
        "data" => {"heading" => "Shop the collection", "intro" => "Explore what we have to offer."}
      }]
    end
  end
end
