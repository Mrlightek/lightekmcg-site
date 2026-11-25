module LightekDesign
  module ContentSections
    def self.definitions
      [{"kind"=>"lightek_feature_showcase", "fields"=>[{"name"=>"showcase_id","label"=>"Saved feature showcase ID","type"=>"text"},{"name"=>"heading","label"=>"Heading","type"=>"text"},{"name"=>"intro","label"=>"Introduction","type"=>"text"}], "data"=>{"heading"=>"Explore the features","intro"=>"See what the platform can do."}},
       {"kind"=>"lightek_blog_index", "fields"=>[{"name"=>"heading","label"=>"Heading","type"=>"text"},{"name"=>"intro","label"=>"Introduction","type"=>"text"}],
        "data"=>{"heading"=>"Journal", "intro"=>"Ideas, stories and updates from our team."}}] + AgencyPortfolio.definitions
    end
  end
end
